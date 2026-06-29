@preconcurrency import AVFoundation
import UIKit
import os

/// Analyzes API thumbnails for face presence and upgrades them by extracting
/// better frames from the video stream when the API thumbnail has no visible face.
///
/// Flow:
/// 1. Analyze the API thumbnail: detect faces
/// 2. If no face found → sample video frames at 25%, 50%, 75%
/// 3. Pick the first frame that contains a face (prefer fully visible)
/// 4. Cache the upgraded thumbnail to disk
actor ThumbnailUpgradeService {
    static let shared = ThumbnailUpgradeService()

    private let diskCache = ThumbnailUpgradeDiskCache()
    private var inFlightItems: Set<String> = []

    /// Limits concurrent AVPlayer frame extractions to avoid overwhelming the media subsystem.
    /// Set to 1 because HLS streams are heavy — even 2 concurrent players cause resource exhaustion on tvOS.
    private let maxConcurrent = 1
    private var activeExtractions = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Public API

    /// Returns the upgraded thumbnail URL from disk cache, or nil if none exists.
    func cachedUpgrade(for itemId: String) async -> URL? {
        await diskCache.cachedFileURL(for: itemId)
    }

    /// Loads an upgraded thumbnail image from disk cache if available.
    func cachedImage(for itemId: String) async -> UIImage? {
        guard let fileURL = await diskCache.cachedFileURL(for: itemId),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }

    /// Evaluates the API thumbnail and upgrades it if needed.
    /// Returns the upgraded UIImage, or nil if the API thumbnail is good enough.
    func upgradeIfNeeded(
        itemId: String,
        thumbnailURL: URL?,
        streamURL: URL?,
        duration: Int
    ) async -> UIImage? {
        // Skip if already processed or in-flight
        guard !inFlightItems.contains(itemId) else { return nil }
        guard await diskCache.cachedFileURL(for: itemId) == nil else { return nil }

        // Need both thumbnail and stream to evaluate
        guard let thumbnailURL, let streamURL else {
            Logger.thumbnail.info("[\(itemId)] skipped: missing thumbnailURL or streamURL")
            return nil
        }

        inFlightItems.insert(itemId)
        defer { inFlightItems.remove(itemId) }

        Logger.thumbnail.info("[\(itemId)] starting analysis (duration=\(duration))")

        do {
            // 1. Load and analyze the API thumbnail
            let thumbImage = try await ImageCacheService.shared.image(for: thumbnailURL)
            guard let cgThumb = thumbImage.cgImage else {
                Logger.thumbnail.info("[\(itemId)] failed: no cgImage from thumbnail")
                return nil
            }

            Logger.thumbnail.info("[\(itemId)] thumbnail loaded: \(cgThumb.width)x\(cgThumb.height)")

            let thumbScore = detectFaces(in: cgThumb)

            Logger.thumbnail.info("[\(itemId)] face=\(thumbScore.hasFace) fullyVisible=\(thumbScore.faceFullyVisible)")

            // If the thumbnail already has a face, keep it
            if thumbScore.hasFace {
                return nil
            }

            // 2. Wait for extraction slot, then extract and score video frames
            Logger.thumbnail.info("[\(itemId)] no face in thumbnail, waiting for extraction slot...")
            await acquireExtractionSlot()

            // A full-screen or PiP player may have started while we waited in the
            // (serialized, maxConcurrent=1) queue. Spinning up a decoder now would
            // starve its audio render thread, so stand down — the requesting card
            // re-runs this once playback ends. Backstops the View-level gate for
            // extractions already queued before the player appeared.
            if await PlaybackCoordinator.shared.isPlaybackActive {
                Logger.thumbnail.info("[\(itemId)] deferred: playback active")
                releaseExtractionSlot()
                return nil
            }
            Logger.thumbnail.info("[\(itemId)] extraction slot acquired, extracting frames...")

            let bestFrame: UIImage?
            do {
                bestFrame = try await extractBestFrame(
                    from: streamURL,
                    duration: duration,
                    baselineScore: thumbScore.total
                )
            } catch {
                releaseExtractionSlot()
                throw error
            }
            releaseExtractionSlot()

            guard let bestFrame else {
                Logger.thumbnail.info("[\(itemId)] no better frame found in video")
                return nil
            }

            // 3. Cache to disk
            await diskCache.save(image: bestFrame, for: itemId)

            Logger.thumbnail.info("Upgraded thumbnail for \(itemId)")
            return bestFrame
        } catch {
            Logger.thumbnail.info("Thumbnail upgrade failed for \(itemId): \(error.localizedDescription)")
            return nil
        }
    }

    /// Clears all cached upgraded thumbnails.
    func clearCache() async {
        await diskCache.clearAll()
    }

    /// Returns disk usage of upgraded thumbnail cache in bytes.
    func cacheSize() async -> Int {
        await diskCache.diskSize()
    }

    // MARK: - Concurrency Throttle

    /// Waits until a slot is available for frame extraction.
    private func acquireExtractionSlot() async {
        if activeExtractions < maxConcurrent {
            activeExtractions += 1
            return
        }
        // Queue until a slot is transferred to us by releaseExtractionSlot.
        // The slot count stays the same (transferred, not released+re-acquired)
        // which avoids actor-reentrancy races.
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Releases a frame extraction slot, or transfers it directly to the next waiter.
    private func releaseExtractionSlot() {
        if !waiters.isEmpty {
            // Transfer the slot to the next waiter (count stays the same)
            let next = waiters.removeFirst()
            next.resume()
        } else {
            activeExtractions -= 1
        }
    }

    // MARK: - Face Detection

    struct ImageScore: Sendable {
        let hasFace: Bool
        let faceFullyVisible: Bool

        var total: Double {
            var score = 0.0
            if hasFace { score += 50 }
            if faceFullyVisible { score += 20 }
            return score
        }
    }

    // CIDetector is thread-safe after creation — cache to avoid per-call allocation
    private nonisolated(unsafe) static let faceDetectorHigh = CIDetector(
        ofType: CIDetectorTypeFace,
        context: nil,
        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
    )

    /// Detects faces in an image using CIDetector (works on all platforms including tvOS simulator).
    private nonisolated func detectFaces(in image: CGImage) -> ImageScore {
        let ciImage = CIImage(cgImage: image)
        let detector = Self.faceDetectorHigh

        guard let faces = detector?.features(in: ciImage) as? [CIFaceFeature], !faces.isEmpty else {
            return ImageScore(hasFace: false, faceFullyVisible: false)
        }

        // Find largest face by area
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        guard let largest = faces.max(by: { $0.bounds.area < $1.bounds.area }) else {
            return ImageScore(hasFace: false, faceFullyVisible: false)
        }

        Logger.thumbnail.info("CIDetector found \(faces.count) face(s), largest: \(Int(largest.bounds.width))x\(Int(largest.bounds.height))")

        // Check if face is fully within frame (with margin)
        // CIDetector uses pixel coordinates (not normalized like Vision)
        let margin: CGFloat = 0.02
        let minX = largest.bounds.minX / imageWidth
        let minY = largest.bounds.minY / imageHeight
        let maxX = largest.bounds.maxX / imageWidth
        let maxY = largest.bounds.maxY / imageHeight
        let fullyVisible = minX >= margin && minY >= margin
            && maxX <= (1.0 - margin) && maxY <= (1.0 - margin)

        return ImageScore(hasFace: true, faceFullyVisible: fullyVisible)
    }

    // MARK: - Frame Extraction (HLS-compatible)

    /// Extracts frames at 25%, 50%, 75% of the video using a single AVPlayer + AVPlayerItemVideoOutput.
    /// Reuses one player and seeks between sample points to minimize resource usage.
    /// Returns the best frame only if it scores higher than the baseline (API thumbnail).
    private func extractBestFrame(
        from streamURL: URL,
        duration: Int,
        baselineScore: Double
    ) async throws -> UIImage? {
        guard duration > 0 else { return nil }

        let totalSeconds = Double(duration)
        let samplePoints: [Double] = [0.25, 0.50, 0.75]

        let frames = try await extractFrames(from: streamURL, atFractions: samplePoints, duration: totalSeconds)

        Logger.thumbnail.info("Extracted \(frames.count) frames from video")

        var bestImage: UIImage?
        var bestScore: Double = baselineScore

        for (index, cgImage) in frames.enumerated() {
            let score = detectFaces(in: cgImage)
            Logger.thumbnail.info("Frame \(index): face=\(score.hasFace) fullyVisible=\(score.faceFullyVisible) total=\(score.total)")
            if score.total > bestScore {
                bestScore = score.total
                bestImage = UIImage(cgImage: cgImage)
            }
        }

        return bestImage
    }

    /// Creates a single AVPlayer, seeks to each sample point, and extracts frames.
    /// Nonisolated because it doesn't access actor state and AVPlayer APIs aren't Sendable.
    private nonisolated func extractFrames(
        from url: URL,
        atFractions fractions: [Double],
        duration: Double
    ) async throws -> [CGImage] {
        Logger.thumbnail.info("extractFrames: loading \(url.lastPathComponent) (duration=\(duration)s)")

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)

        let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        playerItem.add(videoOutput)

        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = true

        // Wait for playerItem to be ready
        Logger.thumbnail.info("extractFrames: waiting for readyToPlay...")
        try await waitForReadyToPlay(playerItem)
        Logger.thumbnail.info("extractFrames: player ready")

        let tolerance = CMTime(seconds: 2, preferredTimescale: 1)
        let ciContext = CIContext()
        var frames: [CGImage] = []

        for fraction in fractions {
            try Task.checkCancellation()
            // The pre-extraction gate only fires once, but readyToPlay + seeks
            // span several seconds. If a player went live in the meantime, this
            // decoder now starves its audio thread — stop sampling and pause.
            if await PlaybackCoordinator.shared.isPlaybackActive {
                Logger.thumbnail.info("extractFrames: playback became active mid-extraction, stopping")
                break
            }
            let targetTime = CMTime(seconds: duration * fraction, preferredTimescale: 600)
            await player.seek(to: targetTime, toleranceBefore: tolerance, toleranceAfter: tolerance)

            // Wait for video output to render the frame
            try await Task.sleep(for: .milliseconds(300))

            let currentTime = playerItem.currentTime()
            let hasBuffer = videoOutput.hasNewPixelBuffer(forItemTime: currentTime)

            guard hasBuffer,
                  let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: currentTime, itemTimeForDisplay: nil) else {
                Logger.thumbnail.info("extractFrames: no pixel buffer at \(Int(fraction * 100))% (hasBuffer=\(hasBuffer))")
                continue
            }

            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            if let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) {
                Logger.thumbnail.info("extractFrames: got frame at \(Int(fraction * 100))% (\(cgImage.width)x\(cgImage.height))")
                frames.append(cgImage)
            }
        }

        player.pause()
        return frames
    }

    /// Waits for AVPlayerItem to reach .readyToPlay status using KVO (with timeout).
    private nonisolated func waitForReadyToPlay(_ item: AVPlayerItem) async throws {
        if item.status == .readyToPlay { return }

        try await withThrowingTaskGroup(of: Void.self) { group in
            // KVO observation for status changes
            group.addTask {
                for await status in item.publisher(for: \.status).values {
                    switch status {
                    case .readyToPlay:
                        return
                    case .failed:
                        throw FrameExtractionError.playerFailed
                    default:
                        continue
                    }
                }
            }
            // Timeout after 10 seconds
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw FrameExtractionError.timeout
            }
            // First to complete wins, cancel the other
            try await group.next()
            group.cancelAll()
        }
    }

    private enum FrameExtractionError: Error {
        case playerFailed
        case timeout
    }
}

// MARK: - Helpers

private extension CGRect {
    var area: CGFloat { width * height }
}
