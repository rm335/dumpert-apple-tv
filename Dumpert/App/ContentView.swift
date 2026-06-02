import SwiftUI

struct ContentView: View {
    @Environment(VideoRepository.self) private var repository
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(ImmersiveBackgroundState.self) private var backgroundState
    @Binding var deepLinkVideoId: String?
    @State private var deepLinkVideo: Video?
    @SceneStorage("selectedTab") private var selectedTab = 0

    var body: some View {
        ZStack {
            ImmersiveBackgroundView(imageURL: backgroundState.activeURL)

            TabView(selection: $selectedTab) {
                ToppersSectionView()
                    .tabItem {
                        Label("Toppers", systemImage: "flame.fill")
                    }
                    .tag(0)

                CategorySectionView(category: .nieuwBinnen)
                    .tabItem {
                        Label("Nieuw", systemImage: "sparkles")
                    }
                    .tag(1)

                CategoriesSectionView()
                    .tabItem {
                        Label(String(localized: "Categorieën", comment: "Categories tab title"), systemImage: "square.grid.2x2.fill")
                    }
                    .tag(2)

                WatchedSectionView()
                    .tabItem {
                        Label(String(localized: "Gekeken", comment: "Watched tab title"), systemImage: "eye.fill")
                    }
                    .tag(3)

                SearchView()
                    .tabItem {
                        Label("Zoeken", systemImage: "magnifyingglass")
                    }
                    .tag(4)

                SettingsView()
                    .tabItem {
                        Label("Instellingen", systemImage: "gearshape.fill")
                    }
                    .tag(5)
            }
        }
        .overlay(alignment: .bottom) {
            if !networkMonitor.isConnected {
                offlineBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: networkMonitor.isConnected)
        .onChange(of: repository.classics) {
            Task { @MainActor in
                backgroundState.shuffleFallback(from: repository.classics)
            }
        }
        .onChange(of: selectedTab) {
            Task { @MainActor in
                backgroundState.shuffleFallback(from: repository.classics)
            }
        }
        .fullScreenCover(item: $deepLinkVideo) { video in
            VideoPlayerView(viewModel: VideoPlayerViewModel(
                video: video,
                repository: repository
            ))
        }
        .onChange(of: deepLinkVideoId) { _, videoId in
            guard let videoId else { return }
            Task { @MainActor in
                deepLinkVideoId = nil
                // Try local data first
                let allItems = repository.hotshiz
                    + repository.topWeek + repository.topMonth
                    + (repository.categoryVideos[.nieuwBinnen] ?? [])
                if let item = allItems.first(where: { $0.id == videoId }),
                   case let .video(video) = item {
                    deepLinkVideo = video
                    return
                }
                // Not found locally — fetch from API
                do {
                    if let item = try await repository.apiClient.fetchItem(id: videoId),
                       case let .video(video) = item {
                        deepLinkVideo = video
                    }
                } catch {
                    // Silently fail — video not available
                }
            }
        }
    }

    /// Connectivity indicator. Floats as a bottom-centered pill so it never
    /// reflows the tab bar (the "dial" must stay put) and never covers the
    /// top tab strip the way a top overlay would.
    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Geen internetverbinding", comment: "Offline banner message")
        }
        .font(.callout)
        .fontWeight(.medium)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .background(.red.opacity(0.6), in: Capsule())
        .padding(.bottom, 40)
    }
}
