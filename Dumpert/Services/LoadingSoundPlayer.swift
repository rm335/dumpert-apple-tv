@preconcurrency import AVFoundation
import os.log

@Observable
@MainActor
final class LoadingSoundPlayer {
    private var audioPlayer: AVAudioPlayer?
    private var fadeTask: Task<Void, Never>?
    private var autoStopTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "nl.dumpert.tvos", category: "sound")
    private let catalog: LoadingSoundCatalog

    init(catalog: LoadingSoundCatalog = .bundled()) {
        self.catalog = catalog
    }

    func playRandom() {
        stop()
        configureAudioSession()
        let urls = eligibleSoundURLs()
        guard let url = urls.randomElement() else {
            logger.warning("No eligible sound files found in bundle")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            player.prepareToPlay()
            guard player.play() else {
                logger.warning("AVAudioPlayer.play() returned false for \(url.lastPathComponent)")
                return
            }
            autoStopTask = Task {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                fadeOutAndStop()
            }
        } catch {
            logger.warning("Failed to play sound: \(error.localizedDescription)")
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
        } catch {
            logger.warning("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    func fadeOutAndStop() {
        autoStopTask?.cancel()
        guard let player = audioPlayer, player.isPlaying else {
            audioPlayer = nil
            return
        }
        fadeTask = Task {
            let originalVolume = player.volume
            let steps = 10
            for step in 1...steps {
                guard !Task.isCancelled else { break }
                player.volume = originalVolume * (1.0 - Float(step) / Float(steps))
                try? await Task.sleep(for: .milliseconds(50))
            }
            player.stop()
            self.audioPlayer = nil
        }
    }

    func stop() {
        autoStopTask?.cancel()
        fadeTask?.cancel()
        audioPlayer?.stop()
        audioPlayer = nil
    }

    /// Bundle sound URLs filtered by the persisted "show NSFW" preference. When
    /// NSFW content is hidden, only catalog-approved (safe-for-work) sounds play.
    private func eligibleSoundURLs() -> [URL] {
        let all = soundURLs()
        guard !Self.nsfwAllowed() else { return all }
        return all.filter { catalog.isSafe(filename: $0.lastPathComponent) }
    }

    /// The persisted "show NSFW" preference, read *synchronously* so the launch
    /// sound never races the asynchronous settings load. Prefers the App Group
    /// mirror (written on every settings save/load, and shared with the Top Shelf
    /// extension) and falls back to the persisted settings snapshot — so even on
    /// the first launch after this feature ships, a user who hid NSFW never hears
    /// an NSFW sound.
    static func nsfwAllowed() -> Bool {
        if let stored = TopShelfDataStore.nsfwEnabledIfSet {
            return stored
        }
        return CacheService.persistedNSFWEnabled()
    }

    private func soundURLs() -> [URL] {
        if let urls = Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: nil), !urls.isEmpty {
            return urls
        }
        if let urls = Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: "Sounds"), !urls.isEmpty {
            return urls
        }
        return []
    }
}
