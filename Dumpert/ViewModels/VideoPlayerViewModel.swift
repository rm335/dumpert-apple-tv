import Foundation
import AVFoundation
import AVKit
import os

@Observable
@MainActor
final class VideoPlayerViewModel {
    private let repository: VideoRepository
    private let nowPlayingService = NowPlayingService()
    let sharePlayService = SharePlayService()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var failedEndObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?

    let video: Video
    let playlist: [Video]
    private(set) var currentIndex: Int
    /// The video that is actively playing right now. Stored explicitly because
    /// related-video autoplay does NOT advance `currentIndex` (it consumes the
    /// head of `relatedVideos` instead), so deriving the current video from
    /// `playlist[currentIndex]` would keep returning the last playlist video
    /// while a related video is on screen — corrupting `saveProgress` and
    /// `markAsWatched` calls.
    private(set) var currentVideo: Video

    var player: AVPlayer?
    weak var playerViewController: AVPlayerViewController?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var isInPiP = false

    // MARK: - Up Next State

    private(set) var showUpNext = false
    private(set) var countdown: Int = 5
    private var upNextCancelled = false
    private var lastSaveTime: Date = .distantPast
    private var preloadedItem: AVPlayerItem?
    /// Populated asynchronously by `checkUpNext` when the user nears the end
    /// of the playlist. `internal` (not `private(set)`) so unit tests can
    /// exercise the related-video autoplay path without spinning up the real
    /// repository or network stack.
    var relatedVideos: [Video] = []
    private var isFetchingRelated = false

    // MARK: - Resume State

    private(set) var showResumeOverlay = false
    private(set) var resumeTimeFormatted = ""
    private var resumeDismissTask: Task<Void, Never>?

    // MARK: - Top Comment State

    private(set) var topComments: [DumpertComment] = []
    private(set) var currentCommentIndex = 0
    private(set) var showTopComment = false
    private var topCommentsFetched = false
    private var topCommentCarouselTask: Task<Void, Never>?

    // MARK: - Now Playing State

    private(set) var showNowPlaying = false
    private(set) var nowPlayingTitle = ""
    private var nowPlayingDismissTask: Task<Void, Never>?


    var currentTopComment: DumpertComment? {
        guard !topComments.isEmpty, currentCommentIndex < topComments.count else { return nil }
        return topComments[currentCommentIndex]
    }

    var autoplayEnabled: Bool { repository.settings.autoplayEnabled }
    private var upNextOverlayEnabled: Bool { repository.settings.upNextOverlayEnabled }
    var upNextCountdownSeconds: Int { repository.settings.upNextCountdownSeconds }
    private var upNextMinimumVideoSeconds: Int { repository.settings.upNextMinimumVideoSeconds }

    var nextVideo: Video? {
        if currentIndex + 1 < playlist.count {
            return playlist[currentIndex + 1]
        }
        return relatedVideos.first
    }

    var hasNextVideo: Bool { nextVideo != nil }

    var previousVideo: Video? {
        guard currentIndex > 0 else { return nil }
        return playlist[currentIndex - 1]
    }

    var hasPreviousVideo: Bool { previousVideo != nil }

    var isSwipeSkipEnabled: Bool {
        repository.settings.remoteSkipMode == .swipe
    }

    let startFromBeginning: Bool

    init(video: Video, playlist: [Video] = [], repository: VideoRepository, startFromBeginning: Bool = false) {
        self.video = video
        self.playlist = playlist
        self.repository = repository
        let startIndex = playlist.firstIndex(of: video) ?? 0
        self.currentIndex = startIndex
        self.currentVideo = playlist.isEmpty ? video : playlist[startIndex]
        self.startFromBeginning = startFromBeginning
    }

    func setupPlayer() {
        guard let url = video.streamURL else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            Logger.network.warning("Audio session setup failed: \(error.localizedDescription)")
        }

        let playerItem = AVPlayerItem(url: url)
        setMetadata(for: currentVideo, on: playerItem)
        player = AVPlayer(playerItem: playerItem)
        observePlaybackStatus()

        if !startFromBeginning {
            resumeIfNeeded(for: currentVideo)
        }

        addTimeObserver()
        addEndObserver()
        fetchTopCommentsIfNeeded(for: video.id)
        configureNowPlaying(for: currentVideo)

        sharePlayService.observeSessions()
        if let player {
            sharePlayService.coordinatePlayback(with: player)
        }
    }

    func configureTransportBar() {
        playerViewController?.speeds = [
            AVPlaybackSpeed(rate: 0.5, localizedName: "0.5×"),
            AVPlaybackSpeed(rate: 0.75, localizedName: "0.75×"),
            AVPlaybackSpeed(rate: 1.0, localizedName: String(localized: "Normaal", comment: "Playback speed label for normal (1x) speed")),
            AVPlaybackSpeed(rate: 1.25, localizedName: "1.25×"),
            AVPlaybackSpeed(rate: 1.5, localizedName: "1.5×"),
            AVPlaybackSpeed(rate: 2.0, localizedName: "2×"),
        ]
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
        saveProgress(force: true)
    }

    func cleanup() {
        if isInPiP { return }

        statusObservation?.invalidate()
        statusObservation = nil
        resumeDismissTask?.cancel()
        resumeDismissTask = nil
        topCommentCarouselTask?.cancel()
        topCommentCarouselTask = nil
        nowPlayingDismissTask?.cancel()
        nowPlayingDismissTask = nil
        saveProgress(force: true)
        nowPlayingService.cleanup()
        sharePlayService.cancelObservation()
        removeTimeObserver()
        removeEndObserver()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        playerViewController?.player = nil
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Up Next Actions

    func skipToNext() {
        showUpNext = false
        playNext()
    }

    func cancelUpNext() {
        upNextCancelled = true
        showUpNext = false
        restorePlayerFocus()
    }

    /// Returns Siri Remote focus to the player surface after the Up Next overlay
    /// is dismissed. That overlay's "Afspelen" button grabs focus when it appears
    /// (so Select plays the next video immediately). When the video then advances
    /// — or the user cancels — the overlay and its focused button are removed, and
    /// tvOS does NOT automatically hand focus back to the AVPlayerViewController.
    /// Focus lands in a black hole: hardware presses route up the responder chain
    /// from the focused view, so with no focused view inside the player hierarchy
    /// the play/pause gesture recognizer on the controller's view never fires and
    /// the freshly started video can't be paused. Forcing a focus update while the
    /// button is still in the hierarchy (this run-loop turn, before SwiftUI removes
    /// it) moves focus back onto the player, because the controller still contains
    /// the focused item at that moment.
    private func restorePlayerFocus() {
        guard let playerViewController else { return }
        playerViewController.setNeedsFocusUpdate()
        playerViewController.updateFocusIfNeeded()
    }

    // MARK: - Progress Tracking

    private func addTimeObserver() {
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = time.seconds
                self.duration = self.player?.currentItem?.duration.seconds ?? 0
                if self.duration.isFinite && self.duration > 0 {
                    self.saveProgress()
                    self.checkUpNext()
                    self.checkTopCommentTiming()
                    self.nowPlayingService.updateProgress(
                        currentTime: self.currentTime,
                        duration: self.duration,
                        rate: self.player?.rate ?? 0
                    )
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func addEndObserver() {
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onVideoFinished(playedToEnd: true)
            }
        }
        failedEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.onVideoFinished(playedToEnd: false)
            }
        }
    }

    private func removeEndObserver() {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }
        if let observer = failedEndObserver {
            NotificationCenter.default.removeObserver(observer)
            failedEndObserver = nil
        }
    }

    /// Tracks the player's timeControlStatus so isPlaying stays in sync
    /// with both programmatic and user-initiated play/pause changes.
    private func observePlaybackStatus() {
        statusObservation = player?.observe(\.timeControlStatus, options: [.old, .new]) { [weak self] player, change in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch player.timeControlStatus {
                case .playing, .waitingToPlayAtSpecifiedRate:
                    self.isPlaying = true
                case .paused:
                    self.isPlaying = false
                    self.saveProgress(force: true)
                @unknown default:
                    break
                }
            }
        }
    }

    private func saveProgress(force: Bool = false) {
        guard duration.isFinite && duration > 0 else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSaveTime) >= 5 else { return }
        lastSaveTime = now
        repository.updateWatchProgress(
            videoId: currentVideo.id,
            watchedSeconds: currentTime,
            totalSeconds: duration
        )
    }

    // MARK: - Up Next Logic

    private func checkUpNext() {
        guard autoplayEnabled,
              !upNextCancelled,
              !sharePlayService.isSharePlayActive else { return }

        let remaining = duration - currentTime

        // Fetch related videos when near the end and playlist is exhausted
        if remaining <= 30 && currentIndex + 1 >= playlist.count
            && relatedVideos.isEmpty && !isFetchingRelated {
            isFetchingRelated = true
            let videoId = currentVideo.id
            Task { [weak self] in
                guard let self else { return }
                self.relatedVideos = await self.repository.fetchRelatedVideos(for: videoId)
                self.isFetchingRelated = false
                if self.preloadedItem == nil, let url = self.nextVideo?.streamURL {
                    self.preloadedItem = AVPlayerItem(url: url)
                }
            }
        }

        guard hasNextVideo else { return }

        // Preload next video when <30s remaining
        if remaining <= 30 && preloadedItem == nil,
           let url = nextVideo?.streamURL {
            preloadedItem = AVPlayerItem(url: url)
        }

        guard upNextOverlayEnabled,
              upNextMinimumVideoSeconds == 0 || duration >= Double(upNextMinimumVideoSeconds) else { return }

        if remaining <= Double(upNextCountdownSeconds) && remaining > 0 {
            if !showUpNext {
                showUpNext = true
            }
            countdown = max(1, Int(remaining.rounded(.up)))
        }
    }

    /// Internal (not private) so unit tests can drive the end-of-playback path
    /// without an `AVPlayer` runtime; production code reaches it only through the
    /// `AVPlayerItemDidPlayToEndTime` / `…FailedToPlayToEndTime` observers.
    func onVideoFinished(playedToEnd: Bool) {
        saveProgress(force: true)

        // Reaching the end of playback is the definitive signal that the video
        // was watched in full, so mark it explicitly. Relying on the 90%
        // threshold in WatchProgress.update is unreliable here: `currentTime`
        // is sampled by a 1s periodic observer and lags the true end by up to a
        // tick, so short clips never cross 0.9 and stay "unwatched". `playNext`
        // marks the current video too, but only when autoplay advances — with
        // autoplay off or on the last/only video, this is the only mark.
        if playedToEnd {
            repository.markAsWatched(videoId: currentVideo.id)
        }
        showUpNext = false

        guard autoplayEnabled && !upNextCancelled else { return }

        if hasNextVideo {
            playNext()
        } else if isFetchingRelated {
            // Related videos worden nog opgehaald — wacht max 2 seconden
            Task { [weak self] in
                for _ in 0..<20 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard let self, self.player != nil else { return }
                    if !self.isFetchingRelated || self.hasNextVideo { break }
                }
                if let self, self.player != nil, self.hasNextVideo {
                    self.playNext()
                }
            }
        }
    }

    func playNext() {
        // Determine the target video BEFORE mutating any state. This avoids
        // incrementing currentIndex or marking the current video as watched
        // when no valid next video exists.
        let targetVideo: Video?
        var newIndex = currentIndex
        if currentIndex + 1 < playlist.count {
            newIndex = currentIndex + 1
            targetVideo = playlist[newIndex]
        } else if let related = relatedVideos.first {
            targetVideo = related
        } else {
            return
        }

        guard let video = targetVideo, let url = video.streamURL else { return }

        // Save progress and mark current video as watched BEFORE changing
        // currentVideo. Otherwise, when replaceCurrentItem triggers a status
        // observation, saveProgress would write the old video's completion
        // state onto the new video's ID — marking it as watched immediately.
        saveProgress(force: true)
        repository.markAsWatched(videoId: currentVideo.id)
        currentTime = 0
        duration = 0

        if newIndex != currentIndex {
            currentIndex = newIndex
        } else {
            relatedVideos.removeFirst()
        }
        // Adopt the new video as the current one BEFORE the time observer is
        // re-added — otherwise the first saveProgress() tick would attribute
        // the new video's playback time to the previous video's id.
        currentVideo = video

        upNextCancelled = false
        showUpNext = false
        resetResume()
        resetTopComment()
        fetchTopCommentsIfNeeded(for: video.id)

        playerViewController?.showsPlaybackControls = false

        removeTimeObserver()
        removeEndObserver()
        let item = preloadedItem ?? AVPlayerItem(url: url)
        setMetadata(for: video, on: item)
        preloadedItem = nil
        player?.replaceCurrentItem(with: item)

        if !startFromBeginning {
            resumeIfNeeded(for: video)
        }

        addTimeObserver()
        addEndObserver()
        player?.play()
        // AVPlayerViewController may reset showsPlaybackControls after
        // replaceCurrentItem/play — force it hidden again.
        playerViewController?.showsPlaybackControls = false
        showNowPlayingBriefly(video.title)
        configureNowPlaying(for: video)
        restorePlayerFocus()
    }

    func playPrevious() {
        guard currentIndex > 0 else { return }

        let newIndex = currentIndex - 1
        let video = playlist[newIndex]
        guard let url = video.streamURL else { return }

        saveProgress(force: true)
        repository.markAsWatched(videoId: currentVideo.id)
        currentTime = 0
        duration = 0

        currentIndex = newIndex
        currentVideo = video

        upNextCancelled = false
        showUpNext = false
        preloadedItem = nil
        resetResume()
        resetTopComment()
        fetchTopCommentsIfNeeded(for: video.id)

        playerViewController?.showsPlaybackControls = false

        removeTimeObserver()
        removeEndObserver()
        let item = AVPlayerItem(url: url)
        setMetadata(for: video, on: item)
        player?.replaceCurrentItem(with: item)

        if !startFromBeginning {
            resumeIfNeeded(for: video)
        }

        addTimeObserver()
        addEndObserver()
        player?.play()
        // AVPlayerViewController may reset showsPlaybackControls after
        // replaceCurrentItem/play — force it hidden again.
        playerViewController?.showsPlaybackControls = false
        showNowPlayingBriefly(video.title)
        configureNowPlaying(for: video)
        restorePlayerFocus()
    }

    // MARK: - Top Comment

    private func fetchTopCommentsIfNeeded(for itemId: String) {
        guard repository.settings.topCommentMode != .off else { return }
        topCommentsFetched = false
        Task {
            do {
                let allComments = try await repository.fetchTopComments(for: itemId)
                let mode = repository.settings.topCommentMode
                switch mode {
                case .off:
                    self.topComments = []
                case .single:
                    // Highest kudos, no minimum
                    if let top = allComments.first {
                        self.topComments = [top]
                    } else {
                        self.topComments = []
                    }
                case .all:
                    // All comments with >= 20 kudos
                    self.topComments = allComments.filter { $0.kudosCount >= 20 }
                }
                Logger.network.debug("Fetched \(allComments.count) comments for \(itemId), filtered to \(self.topComments.count)")
            } catch {
                Logger.network.error("Failed to fetch comments for \(itemId): \(error)")
                self.topComments = []
            }
            self.topCommentsFetched = true

            // If video resumed past the 10-15s timing window, start carousel after a brief delay
            if !topComments.isEmpty && currentTime >= 15 && topCommentCarouselTask == nil {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, topCommentCarouselTask == nil else { return }
                startTopCommentCarousel()
            }
        }
    }

    private func checkTopCommentTiming() {
        guard repository.settings.topCommentMode != .off,
              topCommentsFetched,
              !showTopComment,
              topCommentCarouselTask == nil,
              currentTime >= 10 && currentTime < 15 else { return }

        startTopCommentCarousel()
    }

    private func startTopCommentCarousel() {
        guard !topComments.isEmpty else { return }
        currentCommentIndex = 0
        showTopComment = true

        topCommentCarouselTask = Task { [weak self] in
            guard let self else { return }
            let speed = self.repository.settings.readingSpeed
            do {
                // Show first comment for dynamic duration based on text length
                let firstDuration = speed.readingDuration(for: self.topComments[0].displayContent)
                try await self.pauseAwareSleep(seconds: firstDuration)
                self.showTopComment = false

                // Cycle through remaining comments
                var index = 1
                while index < self.topComments.count {
                    // 5 second gap between comments
                    try await self.pauseAwareSleep(seconds: 5)
                    self.currentCommentIndex = index
                    self.showTopComment = true

                    // Show comment for dynamic duration based on text length
                    let duration = speed.readingDuration(for: self.topComments[index].displayContent)
                    try await self.pauseAwareSleep(seconds: duration)
                    self.showTopComment = false
                    index += 1
                }
            } catch {
                // Task cancelled during cleanup
            }
        }
    }

    /// Sleeps for the given duration, pausing the countdown while the video is paused.
    private func pauseAwareSleep(seconds: Double) async throws {
        let tick: Duration = .milliseconds(250)
        var remaining = seconds
        while remaining > 0 {
            try Task.checkCancellation()
            try await Task.sleep(for: tick)
            if isPlaying {
                remaining -= 0.25
            }
        }
    }

    private func resetTopComment() {
        topCommentCarouselTask?.cancel()
        topCommentCarouselTask = nil
        topComments = []
        currentCommentIndex = 0
        showTopComment = false
        topCommentsFetched = false
    }

    // MARK: - Resume Playback

    private func resumeIfNeeded(for video: Video) {
        guard let progress = repository.watchProgress[video.id],
              progress.watchedSeconds >= 5 else { return }

        let seekTime = CMTime(seconds: progress.watchedSeconds, preferredTimescale: 600)
        player?.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)

        if repository.settings.showResumeOverlay {
            resumeTimeFormatted = Int(progress.watchedSeconds).formattedDuration
            showResumeOverlay = true
            resumeDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.showResumeOverlay = false
            }
        }
    }

    func playFromBeginning() {
        resumeDismissTask?.cancel()
        resumeDismissTask = nil
        showResumeOverlay = false
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func resetResume() {
        resumeDismissTask?.cancel()
        resumeDismissTask = nil
        showResumeOverlay = false
        resumeTimeFormatted = ""
    }

    // MARK: - Now Playing Overlay

    private func showNowPlayingBriefly(_ title: String) {
        nowPlayingDismissTask?.cancel()
        nowPlayingTitle = title
        showNowPlaying = true
        nowPlayingDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            self?.showNowPlaying = false
        }
    }

    // MARK: - Player Metadata

    private func configureNowPlaying(for video: Video) {
        var nextHandler: (@MainActor @Sendable () -> Void)?
        if hasNextVideo {
            nextHandler = { [weak self] in self?.playNext() }
        }

        var prevHandler: (@MainActor @Sendable () -> Void)?
        if hasPreviousVideo {
            prevHandler = { [weak self] in self?.playPrevious() }
        }

        nowPlayingService.configure(
            title: video.title,
            thumbnailURL: video.thumbnailURL,
            duration: Double(video.duration),
            onPlay: { [weak self] in self?.player?.play() },
            onPause: { [weak self] in self?.player?.pause(); self?.saveProgress(force: true) },
            onSkipForward: { [weak self] in
                guard let self, let player = self.player else { return }
                let target = CMTime(seconds: player.currentTime().seconds + 15, preferredTimescale: 600)
                player.seek(to: target)
            },
            onSkipBackward: { [weak self] in
                guard let self, let player = self.player else { return }
                let target = CMTime(seconds: max(0, player.currentTime().seconds - 15), preferredTimescale: 600)
                player.seek(to: target)
            },
            onSeek: { [weak self] (position: TimeInterval) in
                let target = CMTime(seconds: position, preferredTimescale: 600)
                self?.player?.seek(to: target)
            },
            onNextTrack: nextHandler,
            onPreviousTrack: prevHandler
        )
    }

    private func setMetadata(for video: Video, on item: AVPlayerItem) {
        let titleItem = AVMutableMetadataItem()
        titleItem.identifier = .commonIdentifierTitle
        titleItem.value = video.title as NSString
        titleItem.extendedLanguageTag = "und"

        var items: [AVMetadataItem] = [titleItem]

        if !video.descriptionText.isEmpty {
            let descItem = AVMutableMetadataItem()
            descItem.identifier = .commonIdentifierDescription
            descItem.value = video.descriptionText as NSString
            descItem.extendedLanguageTag = "und"
            items.append(descItem)
        }

        item.externalMetadata = items
    }
}
