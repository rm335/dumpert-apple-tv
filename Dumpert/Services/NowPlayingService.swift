import MediaPlayer
import os

@MainActor
final class NowPlayingService {
    private var commandTargets: [Any] = []
    private var artworkTask: Task<Void, Never>?
    private nonisolated static let logger = Logger(subsystem: "nl.dumpert.tvos", category: "nowplaying")

    func configure(
        title: String,
        thumbnailURL: URL?,
        duration: Double,
        onPlay: @escaping @MainActor () -> Void,
        onPause: @escaping @MainActor () -> Void,
        onSkipForward: @escaping @MainActor () -> Void,
        onSkipBackward: @escaping @MainActor () -> Void,
        onSeek: @escaping @MainActor (TimeInterval) -> Void,
        onNextTrack: (@MainActor () -> Void)? = nil,
        onPreviousTrack: (@MainActor () -> Void)? = nil
    ) {
        // Reset first: cleanup() clears the info, so it must run before we publish the new title.
        cleanup()

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]

        configureCommands(
            onPlay: onPlay,
            onPause: onPause,
            onSkipForward: onSkipForward,
            onSkipBackward: onSkipBackward,
            onSeek: onSeek,
            onNextTrack: onNextTrack,
            onPreviousTrack: onPreviousTrack
        )

        if let thumbnailURL {
            loadArtwork(from: thumbnailURL)
        }
    }

    func updateProgress(currentTime: Double, duration: Double, rate: Float) {
        let center = MPNowPlayingInfoCenter.default()
        var info = center.nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        center.nowPlayingInfo = info
    }

    func cleanup() {
        artworkTask?.cancel()
        artworkTask = nil
        let commandCenter = MPRemoteCommandCenter.shared()
        for target in commandTargets {
            commandCenter.playCommand.removeTarget(target)
            commandCenter.pauseCommand.removeTarget(target)
            commandCenter.skipForwardCommand.removeTarget(target)
            commandCenter.skipBackwardCommand.removeTarget(target)
            commandCenter.changePlaybackPositionCommand.removeTarget(target)
            commandCenter.nextTrackCommand.removeTarget(target)
            commandCenter.previousTrackCommand.removeTarget(target)
        }
        commandTargets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    // MARK: - Private

    private func configureCommands(
        onPlay: @escaping @MainActor () -> Void,
        onPause: @escaping @MainActor () -> Void,
        onSkipForward: @escaping @MainActor () -> Void,
        onSkipBackward: @escaping @MainActor () -> Void,
        onSeek: @escaping @MainActor (TimeInterval) -> Void,
        onNextTrack: (@MainActor () -> Void)?,
        onPreviousTrack: (@MainActor () -> Void)?
    ) {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        let playTarget = commandCenter.playCommand.addTarget { _ in
            Task { @MainActor in onPlay() }
            return .success
        }
        commandTargets.append(playTarget)

        commandCenter.pauseCommand.isEnabled = true
        let pauseTarget = commandCenter.pauseCommand.addTarget { _ in
            Task { @MainActor in onPause() }
            return .success
        }
        commandTargets.append(pauseTarget)

        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipForwardCommand.preferredIntervals = [15]
        let skipFwdTarget = commandCenter.skipForwardCommand.addTarget { _ in
            Task { @MainActor in onSkipForward() }
            return .success
        }
        commandTargets.append(skipFwdTarget)

        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.preferredIntervals = [15]
        let skipBwdTarget = commandCenter.skipBackwardCommand.addTarget { _ in
            Task { @MainActor in onSkipBackward() }
            return .success
        }
        commandTargets.append(skipBwdTarget)

        commandCenter.changePlaybackPositionCommand.isEnabled = true
        let seekTarget = commandCenter.changePlaybackPositionCommand.addTarget { event in
            guard let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in onSeek(positionEvent.positionTime) }
            return .success
        }
        commandTargets.append(seekTarget)

        // Next/previous track commands (enabled when playlist has adjacent videos)
        if let onNextTrack {
            commandCenter.nextTrackCommand.isEnabled = true
            let nextTarget = commandCenter.nextTrackCommand.addTarget { _ in
                Task { @MainActor in onNextTrack() }
                return .success
            }
            commandTargets.append(nextTarget)
        } else {
            commandCenter.nextTrackCommand.isEnabled = false
        }

        if let onPreviousTrack {
            commandCenter.previousTrackCommand.isEnabled = true
            let prevTarget = commandCenter.previousTrackCommand.addTarget { _ in
                Task { @MainActor in onPreviousTrack() }
                return .success
            }
            commandTargets.append(prevTarget)
        } else {
            commandCenter.previousTrackCommand.isEnabled = false
        }
    }

    private func loadArtwork(from url: URL) {
        artworkTask = Task.detached(priority: .utility) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                await MainActor.run {
                    // cleanup() runs on the main actor too, so a cancel is seen here race-free.
                    guard !Task.isCancelled else { return }
                    var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                    info[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
                }
            } catch {
                Self.logger.warning("Failed to load artwork: \(error.localizedDescription)")
            }
        }
    }
}
