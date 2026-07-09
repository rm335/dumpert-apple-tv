import SwiftUI
import os

struct ContentView: View {
    @Environment(VideoRepository.self) private var repository
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(ImmersiveBackgroundState.self) private var backgroundState
    @Binding var deepLinkVideoId: String?
    @State private var deepLinkVideo: Video?
    @State private var deepLinkPhoto: Photo?
    @State private var toastMessage: String?
    @SceneStorage("selectedTab") private var selectedTab = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ImmersiveBackgroundView()

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
        .animation(reduceMotion ? nil : .smooth, value: networkMonitor.isConnected)
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
            // .id ties the player's identity (and its @State view model) to the
            // video: a second deep link arriving while this cover is up swaps
            // the item in place, and without the identity change the old
            // video would keep playing under the new title.
            VideoPlayerView(video: video, repository: repository)
                .id(video.id)
        }
        .fullScreenCover(item: $deepLinkPhoto) { photo in
            FullScreenImageView(photo: photo, repository: repository)
        }
        .toast(message: $toastMessage)
        .onChange(of: deepLinkVideoId) { _, videoId in
            guard let videoId else { return }
            Task { @MainActor in
                deepLinkVideoId = nil

                // Clear the stage first: a section's presented player/photo
                // cover blocks the root-level presentation below (UIKit
                // refuses a second concurrent present — the Top Shelf tap
                // would visibly do nothing). The takeover signal makes every
                // section dismiss its covers; then give the dismissal
                // animation room before presenting ours.
                // ponytail: fixed 800ms grace instead of a completion
                // handshake across five section views. On cold launch the
                // loading screen absorbs the delay.
                PlaybackCoordinator.shared.requestDeepLinkTakeover()
                deepLinkVideo = nil
                deepLinkPhoto = nil
                try? await Task.sleep(for: .milliseconds(800))

                // Try local data first. Include topDay (Top Vandaag) — a video that
                // only lives there would otherwise miss the in-memory lookup.
                let allItems = repository.hotshiz
                    + repository.topWeek + repository.topMonth + repository.topDay
                    + (repository.categoryVideos[.nieuwBinnen] ?? [])
                if let item = allItems.first(where: { $0.id == videoId }) {
                    item.present(selectedVideo: $deepLinkVideo, selectedPhoto: $deepLinkPhoto)
                    return
                }
                // Not found locally — fetch from API. Failures get a toast:
                // a tapped Top Shelf item that silently does nothing reads
                // as a broken app.
                do {
                    if let item = try await repository.apiClient.fetchItem(id: videoId) {
                        item.present(selectedVideo: $deepLinkVideo, selectedPhoto: $deepLinkPhoto)
                    } else {
                        toastMessage = String(localized: "Video niet gevonden", comment: "Toast when a deep-linked video does not exist")
                    }
                } catch {
                    Logger.network.warning("Deep link fetch failed for \(videoId): \(error.localizedDescription)")
                    toastMessage = String(localized: "Kon video niet laden", comment: "Toast when a deep-linked video fails to load")
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
        .background(Color.dumpiError.opacity(0.55), in: Capsule())
        .padding(.bottom, 40)
    }
}
