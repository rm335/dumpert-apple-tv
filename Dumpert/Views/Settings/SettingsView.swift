import SwiftUI

struct SettingsView: View {
    @Environment(VideoRepository.self) private var repository
    @Environment(ImmersiveBackgroundState.self) private var backgroundState
    @State private var showClearCacheConfirmation = false
    @State private var showCacheClearedFeedback = false
    @State private var showClearHistoryConfirmation = false
    @State private var showHistoryClearedFeedback = false
    @State private var showClearSearchHistoryConfirmation = false
    @State private var showSearchHistoryClearedFeedback = false
    @State private var showResetConfirmation = false
    @State private var showResetFeedback = false
    @State private var isRefreshing = false
    @State private var showRefreshFeedback = false
    @State private var cacheSize: String?

    var body: some View {
        @Bindable var settings = repository.settings

        NavigationStack {
            List {
            // MARK: - Content (what shows up)

            Section {
                settingsNavigationPicker(
                    "Minimale kudos",
                    icon: "arrow.up.heart.fill",
                    description: "Verberg video's onder dit aantal",
                    selection: $settings.minimumKudos,
                    options: [
                        ("Alles tonen", 0),
                        ("10+ kudos", 10),
                        ("25+ kudos", 25),
                        ("50+ kudos", 50),
                        ("100+ kudos", 100),
                        ("250+ kudos", 250),
                        ("500+ kudos", 500),
                    ]
                )

                settingsToggle(
                    "NSFW-content tonen",
                    icon: "eye.trianglebadge.exclamationmark",
                    description: "Toon content die als niet-veilig-voor-werk is gemarkeerd",
                    isOn: $settings.nsfwEnabled
                )

                settingsToggle(
                    "Negatieve kudos tonen",
                    icon: "hand.thumbsdown",
                    description: "Toon video's met meer downvotes dan upvotes",
                    isOn: $settings.showNegativeKudos
                )

                settingsToggle(
                    "Bekeken verbergen",
                    icon: "eye.slash",
                    description: "Verberg video's die je al hebt gezien",
                    isOn: $settings.hideWatched
                )

                settingsNavigationPicker(
                    "Minimale reeten-duur",
                    icon: "timer",
                    description: "Alleen in de Reeten-tab: verberg korte video's",
                    selection: $settings.reetenMinimumMinutes,
                    options: [
                        ("Geen minimum", 0),
                        ("5 minuten", 5),
                        ("10 minuten", 10),
                        ("15 minuten", 15),
                        ("20 minuten", 20),
                    ]
                )
            } header: {
                sectionHeader("Content")
            }

            // MARK: - Weergave (how it looks)

            Section {
                settingsToggle(
                    "Slimme thumbnails",
                    icon: "sparkles.rectangle.stack",
                    description: "Verbeter thumbnails automatisch met een beter videoframe",
                    isOn: $settings.smartThumbnailsEnabled
                )

                settingsNavigationPicker(
                    "Kaartgrootte",
                    icon: "square.grid.2x2",
                    description: "Aantal kolommen in de video-overzichten",
                    selection: $settings.tileSize,
                    options: [
                        ("Klein", TileSize.small),
                        ("Normaal", TileSize.normal),
                        ("Groot", TileSize.large),
                    ]
                )

                tilePreview(columnCount: settings.tileSize.gridColumnCount, tileSize: settings.tileSize)
            } header: {
                sectionHeader("Weergave")
            }

            // MARK: - Afspelen

            Section {
                settingsToggle(
                    "Autoplay",
                    icon: "play.circle",
                    description: "Speel automatisch de volgende video af",
                    isOn: $settings.autoplayEnabled
                )

                settingsToggle(
                    "Video voorvertoning",
                    icon: "film",
                    description: "Speel een preview bij focus op een video",
                    isOn: $settings.thumbnailPreviewEnabled
                )

                NavigationLink {
                    UpNextSettingsView()
                } label: {
                    settingsLabel(
                        "Volgende video",
                        icon: "forward.end",
                        description: "Overlay, aftelling en minimale videolengte"
                    )
                }

                settingsNavigationPicker(
                    "Reaguursels",
                    icon: "text.bubble",
                    description: "Toon populaire reacties als overlay tijdens afspelen",
                    selection: $settings.topCommentMode,
                    options: [
                        ("Uit", TopCommentMode.off),
                        ("Alleen het top reaguursel", TopCommentMode.single),
                        ("Alle reaguursels", TopCommentMode.all),
                    ]
                )

                settingsNavigationPicker(
                    "Leessnelheid",
                    icon: "text.word.spacing",
                    description: "Hoe lang reaguursels in beeld blijven",
                    selection: $settings.readingSpeed,
                    options: [
                        ("Langzaam (2 woorden/sec)", ReadingSpeed.slow),
                        ("Normaal (3 woorden/sec)", ReadingSpeed.normal),
                        ("Snel (4 woorden/sec)", ReadingSpeed.fast),
                        ("Zeer snel (5 woorden/sec)", ReadingSpeed.veryFast),
                        ("Razendsnel (6 woorden/sec)", ReadingSpeed.ultraFast),
                    ]
                )

                settingsToggle(
                    "Swipe om over te slaan",
                    icon: "appletvremote.gen4",
                    description: "Swipe links/rechts op het touchpad voor vorige/volgende video",
                    isOn: Binding(
                        get: { settings.remoteSkipMode == .swipe },
                        set: { settings.remoteSkipMode = $0 ? .swipe : .off }
                    )
                )

                settingsToggle(
                    "Hervat-melding",
                    icon: "arrow.uturn.backward.circle",
                    description: "Toon een melding wanneer een video wordt hervat",
                    isOn: $settings.showResumeOverlay
                )

            } header: {
                sectionHeader("Afspelen")
            }

            // MARK: - Data & opslag

            Section {
                Button {
                    guard !isRefreshing else { return }
                    isRefreshing = true
                    Task {
                        await repository.refreshAll()
                        isRefreshing = false
                        showRefreshFeedback = true
                    }
                } label: {
                    HStack {
                        settingsLabel(
                            "Nu verversen",
                            icon: "arrow.clockwise",
                            description: "Haal de nieuwste content op"
                        )
                        Spacer()
                        if isRefreshing {
                            ProgressView()
                        } else if showRefreshFeedback {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.dumpiGreen)
                                .transition(.scale.combined(with: .opacity))
                        } else if let lastRefresh = repository.lastRefreshDate {
                            Text("Laatst: \(lastRefresh, style: .relative)", comment: "Last refresh time indicator")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                    }
                }
                .disabled(isRefreshing)

                Button {
                    showClearCacheConfirmation = true
                } label: {
                    HStack {
                        destructiveLabel(
                            "Cache wissen",
                            icon: "trash",
                            description: "Verwijder opgeslagen afbeeldingen en API-data"
                        )
                        Spacer()
                        if showCacheClearedFeedback {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.dumpiGreen)
                                .transition(.scale.combined(with: .opacity))
                        } else if let size = cacheSize {
                            Text(size)
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
                .confirmationDialog(Text("Cache wissen", comment: "Cache clear confirmation title"), isPresented: $showClearCacheConfirmation) {
                    Button(String(localized: "Cache wissen", comment: "Cache clear confirmation title"), role: .destructive) {
                        Task {
                            await repository.clearAllCaches()
                            showCacheClearedFeedback = true
                            cacheSize = nil
                        }
                    }
                    Button(String(localized: "Annuleer", comment: "Cancel button"), role: .cancel) {}
                } message: {
                    Text("Alle opgeslagen afbeeldingen en API-responses worden verwijderd.", comment: "Cache clear confirmation message")
                }

                Button {
                    showClearHistoryConfirmation = true
                } label: {
                    HStack {
                        destructiveLabel(
                            "Kijkgeschiedenis wissen",
                            icon: "clock.arrow.circlepath",
                            description: "Alle video's worden weer als onbekeken getoond"
                        )
                        Spacer()
                        if showHistoryClearedFeedback {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.dumpiGreen)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .confirmationDialog(Text("Kijkgeschiedenis wissen", comment: "Watch history clear confirmation title"), isPresented: $showClearHistoryConfirmation) {
                    Button(String(localized: "Wis geschiedenis", comment: "Watch history clear button"), role: .destructive) {
                        Task {
                            await repository.clearWatchHistory()
                            showHistoryClearedFeedback = true
                        }
                    }
                    Button(String(localized: "Annuleer", comment: "Cancel button"), role: .cancel) {}
                } message: {
                    Text("Alle bekeken video's worden weer als onbekeken getoond.", comment: "Watch history clear confirmation message")
                }
                Button {
                    showClearSearchHistoryConfirmation = true
                } label: {
                    HStack {
                        destructiveLabel(
                            "Zoekgeschiedenis wissen",
                            icon: "magnifyingglass",
                            description: "Alle recente zoekopdrachten worden verwijderd"
                        )
                        Spacer()
                        if showSearchHistoryClearedFeedback {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.dumpiGreen)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                }
                .confirmationDialog(Text("Zoekgeschiedenis wissen", comment: "Search history clear confirmation title"), isPresented: $showClearSearchHistoryConfirmation) {
                    Button(String(localized: "Wis zoekgeschiedenis", comment: "Search history clear button"), role: .destructive) {
                        repository.clearSearchHistory()
                        showSearchHistoryClearedFeedback = true
                    }
                    Button(String(localized: "Annuleer", comment: "Cancel button"), role: .cancel) {}
                } message: {
                    Text("Alle opgeslagen zoekopdrachten worden verwijderd.", comment: "Search history clear confirmation message")
                }
            } header: {
                sectionHeader("Data & opslag")
            }

            // MARK: - Over

            Section {
                infoRow("Versie", icon: "info.circle", value: "\(Self.appVersion)")
                infoRow("Automatisch verversen", icon: "clock", value: "Elke 15 minuten")

                HStack(spacing: 28) {
                    Image(systemName: "icloud")
                        .frame(width: 28)
                    Text("iCloud sync")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.dumpiGreen)
                            .frame(width: 8, height: 8)
                        Text(settings.lastModified, style: .relative)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }

                Button {
                    showResetConfirmation = true
                } label: {
                    destructiveLabel(
                        "Herstel standaardwaarden",
                        icon: "arrow.counterclockwise",
                        description: "Zet alle instellingen terug naar fabrieksinstellingen"
                    )
                }
                .confirmationDialog(Text("Standaardwaarden herstellen", comment: "Reset defaults confirmation title"), isPresented: $showResetConfirmation) {
                    Button(String(localized: "Herstel standaardwaarden", comment: "Reset defaults button"), role: .destructive) {
                        withAnimation(.smooth) {
                            settings.resetToDefaults()
                        }
                        showResetFeedback = true
                    }
                    Button(String(localized: "Annuleer", comment: "Cancel button"), role: .cancel) {}
                } message: {
                    Text("Alle instellingen worden teruggezet. Dit kan niet ongedaan worden gemaakt.", comment: "Reset defaults confirmation message")
                }
            } header: {
                sectionHeader("Over")
            }
            }
        } // NavigationStack
        .task {
            await loadCacheSize()
        }
        .task {
            backgroundState.useFallback()
        }
        .autoDismiss($showRefreshFeedback)
        .autoDismiss($showHistoryClearedFeedback)
        .autoDismiss($showSearchHistoryClearedFeedback)
        .autoDismiss($showResetFeedback)
        .onChange(of: settings.nsfwEnabled) {
            Task { @MainActor in
                repository.syncNSFWSetting()
            }
        }
        .onChange(of: showCacheClearedFeedback) {
            if showCacheClearedFeedback {
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation(.smooth) { showCacheClearedFeedback = false }
                    await loadCacheSize()
                }
            }
        }
    }

    private static let byteCountFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useKB]
        f.countStyle = .file
        return f
    }()

    private func loadCacheSize() async {
        let totalBytes = await repository.totalCacheSize()
        cacheSize = Self.byteCountFormatter.string(fromByteCount: Int64(totalBytes))
    }
}
