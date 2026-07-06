import SwiftUI

@main
struct DumpertApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var videoRepository = VideoRepository()
    @State private var networkMonitor = NetworkMonitor()
    @State private var backgroundState = ImmersiveBackgroundState()
    @State private var deepLinkVideoId: String?
    @State private var soundPlayer = LoadingSoundPlayer()
    @State private var showLoadingScreen = true
    @State private var backgroundDate: Date?

    init() {
        SentryMonitoring.start()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(deepLinkVideoId: $deepLinkVideoId)
                    .onOpenURL { url in
                        guard url.scheme == "dumpert",
                              url.host == "video" else { return }
                        deepLinkVideoId = url.lastPathComponent
                    }

                if showLoadingScreen {
                    LoadingScreenView {
                        showLoadingScreen = false
                    }
                }
            }
            .environment(videoRepository)
            .environment(networkMonitor)
            .environment(backgroundState)
            .environment(soundPlayer)
            .tint(.dumpiGreen)
            // The whole app is designed on a black immersive background with
            // semantic text colors — in the system Light appearance those flip
            // to near-black-on-black. Dark is the only supported appearance.
            .preferredColorScheme(.dark)
            .task {
                videoRepository.networkMonitor = networkMonitor
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                backgroundDate = Date()
            case .active:
                if let bgDate = backgroundDate,
                   Date().timeIntervalSince(bgDate) >= 300 {
                    // With a player presented (full-screen or PiP) the loading
                    // screen would be invisible behind the cover — but its
                    // onAppear would still blast a random sound over the video.
                    if !PlaybackCoordinator.shared.isPlaybackActive {
                        showLoadingScreen = true
                    }
                    Task { await videoRepository.refreshAll() }
                }
                backgroundDate = nil
            default:
                break
            }
        }
    }
}
