import SwiftUI
import AVKit

struct VideoPlayerView: View {
    @Environment(LoadingSoundPlayer.self) private var soundPlayer
    /// Owned in @State so the SAME view model survives re-evaluations of the
    /// enclosing `fullScreenCover` content closure. Those closures read
    /// @Observable repository state (feeds, watchProgress) that mutates every
    /// ~5s during playback (saveProgress); with a plain `let` each re-render
    /// swapped in a fresh, inert view model while the real player kept running
    /// on the original — so cleanup() ran on the wrong instance, leaving
    /// PlaybackCoordinator wedged (focus previews dead for the session) and
    /// PiP audio/now-playing torn down mid-session.
    @State private var viewModel: VideoPlayerViewModel

    init(
        video: Video,
        playlist: [Video] = [],
        repository: VideoRepository,
        startFromBeginning: Bool = false
    ) {
        // State(initialValue:) constructs a throwaway VM on each closure
        // re-run, but VideoPlayerViewModel.init is side-effect free — only the
        // first instance is retained and ever calls setupPlayer()/cleanup().
        _viewModel = State(initialValue: VideoPlayerViewModel(
            video: video,
            playlist: playlist,
            repository: repository,
            startFromBeginning: startFromBeginning
        ))
    }

    var body: some View {
        PlayerRepresentable(viewModel: viewModel)
            .ignoresSafeArea()
            .onAppear {
                soundPlayer.fadeOutAndStop()
            }
            .onDisappear {
                if !viewModel.isInPiP {
                    viewModel.cleanup()
                }
            }
    }
}

// MARK: - AVPlayerViewController Wrapper

private struct PlayerRepresentable: UIViewControllerRepresentable {
    let viewModel: VideoPlayerViewModel

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.allowsPictureInPicturePlayback = true
        viewModel.setupPlayer()
        viewModel.playerViewController = controller
        controller.player = viewModel.player
        controller.delegate = context.coordinator

        let overlay = UpNextOverlayContainer(viewModel: viewModel)
        let hosting = UIHostingController(rootView: overlay)
        hosting.view.backgroundColor = .clear
        hosting.view.isUserInteractionEnabled = true
        hosting.view.translatesAutoresizingMaskIntoConstraints = false

        controller.addChild(hosting)
        if let contentOverlay = controller.contentOverlayView {
            contentOverlay.addSubview(hosting.view)
            NSLayoutConstraint.activate([
                hosting.view.topAnchor.constraint(equalTo: contentOverlay.topAnchor),
                hosting.view.bottomAnchor.constraint(equalTo: contentOverlay.bottomAnchor),
                hosting.view.leadingAnchor.constraint(equalTo: contentOverlay.leadingAnchor),
                hosting.view.trailingAnchor.constraint(equalTo: contentOverlay.trailingAnchor),
            ])
        }
        hosting.didMove(toParent: controller)

        // Play/pause is ALWAYS intercepted so AVPlayerViewController's native
        // handler can never seek to a stale transport bar position (0:00).
        // Select is only intercepted while controls are hidden to reveal them.
        let playPauseTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePlayPause))
        playPauseTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        controller.view.addGestureRecognizer(playPauseTap)
        context.coordinator.playPauseGesture = playPauseTap

        let selectTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSelect))
        selectTap.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        selectTap.delegate = context.coordinator
        controller.view.addGestureRecognizer(selectTap)

        // Swipe gestures for next/previous video
        let swipeRight = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeRight))
        swipeRight.direction = .right
        swipeRight.delegate = context.coordinator
        controller.view.addGestureRecognizer(swipeRight)
        context.coordinator.swipeRightGesture = swipeRight

        let swipeLeft = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeLeft))
        swipeLeft.direction = .left
        swipeLeft.delegate = context.coordinator
        controller.view.addGestureRecognizer(swipeLeft)
        context.coordinator.swipeLeftGesture = swipeLeft

        viewModel.configureTransportBar()
        viewModel.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        // Overlay updates handled by @Observable viewModel
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    @MainActor
    class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate, UIGestureRecognizerDelegate {
        private let viewModel: VideoPlayerViewModel
        var playPauseGesture: UITapGestureRecognizer?
        var swipeLeftGesture: UISwipeGestureRecognizer?
        var swipeRightGesture: UISwipeGestureRecognizer?

        init(viewModel: VideoPlayerViewModel) {
            self.viewModel = viewModel
        }

        func playerViewControllerWillBeginDismissalTransition(_ playerViewController: AVPlayerViewController) {
            if !viewModel.isInPiP {
                viewModel.cleanup()
            }
        }

        // MARK: - Picture in Picture

        func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            viewModel.isInPiP = true
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            viewModel.isInPiP = false
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }

        // MARK: - Remote Control Handling

        /// Play/pause is always handled by us (no delegate check needed —
        /// that gesture has no delegate set). Select is only intercepted
        /// while controls are hidden; once visible, native handling takes over.
        /// Swipe gestures also require controls hidden + no interactive overlay + setting enabled.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // Swipe gestures: allowed when no overlay is active, setting is enabled,
            // and there is actually a next/previous video to skip to.
            if gestureRecognizer === swipeRightGesture {
                let noOverlay = !viewModel.showUpNext && !viewModel.showResumeOverlay
                return noOverlay && viewModel.isSwipeSkipEnabled && viewModel.hasNextVideo
            }
            if gestureRecognizer === swipeLeftGesture {
                let noOverlay = !viewModel.showUpNext && !viewModel.showResumeOverlay
                return noOverlay && viewModel.isSwipeSkipEnabled && viewModel.hasPreviousVideo
            }

            // Select gesture: only when controls hidden (to reveal them)
            return viewModel.playerViewController?.showsPlaybackControls == false
        }

        @objc func handlePlayPause() {
            guard let player = viewModel.player else { return }
            if player.timeControlStatus == .paused {
                player.play()
            } else {
                player.pause()
            }
            viewModel.playerViewController?.showsPlaybackControls = true
        }

        @objc func handleSelect() {
            viewModel.playerViewController?.showsPlaybackControls = true
        }

        // MARK: - Swipe Skip Gestures

        @objc func handleSwipeRight() {
            viewModel.skipToNext()
        }

        @objc func handleSwipeLeft() {
            viewModel.playPrevious()
        }
    }
}

// MARK: - UpNext Overlay Container

/// Wrapper that observes the viewModel and shows/hides the UpNext overlay.
/// Hosted inside AVPlayerViewController's contentOverlayView so it renders
/// above the video on tvOS.
private struct UpNextOverlayContainer: View {
    let viewModel: VideoPlayerViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Resume overlay (top-left)
            ResumeOverlayView(
                formattedTime: viewModel.resumeTimeFormatted,
                isVisible: viewModel.showResumeOverlay,
                onPlayFromBeginning: { viewModel.playFromBeginning() }
            )

            // Now playing title (top-center, shown briefly on autoplay)
            NowPlayingOverlayView(
                title: viewModel.nowPlayingTitle,
                isVisible: viewModel.showNowPlaying
            )

            // SharePlay indicator (top-right)
            SharePlayIndicatorView(
                participantCount: viewModel.sharePlayService.participantCount,
                isVisible: viewModel.sharePlayService.isSharePlayActive
            )

            // Top comment overlay (bottom-left). Suppressed while the Up Next
            // card is up so only one bottom-zone overlay competes for attention —
            // the playback decision outranks a comment in the Theater.
            TopCommentOverlayView(
                comment: viewModel.currentTopComment,
                isVisible: viewModel.showTopComment && !viewModel.showUpNext
            )

            // Up next overlay (bottom-right)
            if viewModel.showUpNext, let next = viewModel.nextVideo {
                UpNextOverlayView(
                    nextVideo: next,
                    countdown: viewModel.countdown,
                    totalCountdown: viewModel.upNextCountdownSeconds,
                    onPlayNow: { viewModel.skipToNext() },
                    onCancel: { viewModel.cancelUpNext() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.2), value: viewModel.showUpNext)
            }
        }
    }
}
