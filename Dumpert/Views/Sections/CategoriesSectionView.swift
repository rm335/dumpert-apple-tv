import SwiftUI

/// Container view that consolidates niche video categories (Reeten, VrijMiCo,
/// Dashcam, Classics) behind a single top-level tab with an in-view pill
/// filter. Reduces top-tab count from 9 → 5 while preserving access to all
/// signature Dumpert collections.
///
/// Selection persists across scene restores via `@SceneStorage` so returning
/// to the tab restores the previously selected sub-category.
struct CategoriesSectionView: View {
    @SceneStorage("categoriesSelectedTab") private var rawSelection: String = CategoryTab.reeten.rawValue
    @FocusState private var focusedPill: CategoryTab?

    private var selection: CategoryTab {
        CategoryTab(rawValue: rawSelection) ?? .reeten
    }

    var body: some View {
        VStack(spacing: 0) {
            pillBar
                .padding(.horizontal, 50)
                .padding(.top, 20)
                .padding(.bottom, 4)

            ZStack {
                switch selection {
                case .reeten:
                    CategorySectionView(category: .reeten, showsTitle: false)
                        .transition(.opacity)
                case .vrijmico:
                    CategorySectionView(category: .vrijmico, showsTitle: false)
                        .transition(.opacity)
                case .dashcam:
                    CategorySectionView(category: .dashcam, showsTitle: false)
                        .transition(.opacity)
                case .classics:
                    ClassicsSectionView(showsHeader: false)
                        .transition(.opacity)
                }
            }
            .id(selection)
            .animation(.easeOut(duration: 0.2), value: selection)
        }
    }

    // MARK: - Pill Bar

    private var pillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(CategoryTab.allCases) { tab in
                    pillButton(for: tab)
                }
            }
            .padding(.vertical, 10)
        }
        .scrollClipDisabled()
    }

    private func pillButton(for tab: CategoryTab) -> some View {
        let isSelected = selection == tab
        let background: Color = isSelected ? .dumpiGreen : .white.opacity(0.12)

        return Button {
            rawSelection = tab.rawValue
        } label: {
            pillLabel(for: tab, background: background)
        }
        .buttonStyle(FocusableCapsuleButtonStyle())
        .focused($focusedPill, equals: tab)
        .accessibilityLabel(Text(tab.accessibilityLabel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func pillLabel(for tab: CategoryTab, background: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tab.systemImage)
            Text(tab.displayName)
        }
        .font(.callout)
        .fontWeight(.semibold)
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(background, in: Capsule())
    }
}

// MARK: - CategoryTab

extension CategoriesSectionView {
    enum CategoryTab: String, CaseIterable, Identifiable, Hashable {
        case reeten
        case vrijmico
        case dashcam
        case classics

        var id: String { rawValue }

        var displayName: LocalizedStringKey {
            switch self {
            case .reeten: "Reeten"
            case .vrijmico: "VrijMiCo"
            case .dashcam: "Dashcam"
            case .classics: "Classics"
            }
        }

        var systemImage: String {
            switch self {
            case .reeten: "trophy.fill"
            case .vrijmico: "party.popper.fill"
            case .dashcam: "car.fill"
            case .classics: "clock.arrow.circlepath"
            }
        }

        var accessibilityLabel: String {
            switch self {
            case .reeten: String(localized: "Reeten", comment: "Accessibility: Reeten sub-tab")
            case .vrijmico: String(localized: "VrijMiCo", comment: "Accessibility: VrijMiCo sub-tab")
            case .dashcam: String(localized: "Dashcam", comment: "Accessibility: Dashcam sub-tab")
            case .classics: String(localized: "Classics", comment: "Accessibility: Classics sub-tab")
            }
        }
    }
}
