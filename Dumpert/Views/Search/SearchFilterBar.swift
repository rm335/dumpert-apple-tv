import SwiftUI

extension SearchView {
    func filterBar(_ viewModel: SearchViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                filterCycleButton(
                    title: viewModel.filter.mediaType.displayName,
                    icon: viewModel.filter.mediaType.icon,
                    isActive: viewModel.filter.mediaType != .all
                ) {
                    let cases = MediaTypeFilter.allCases
                    let idx = cases.firstIndex(of: viewModel.filter.mediaType) ?? cases.startIndex
                    viewModel.filter.mediaType = cases[(cases.distance(from: cases.startIndex, to: idx) + 1) % cases.count]
                }

                filterCycleButton(
                    title: viewModel.filter.period.displayName,
                    icon: viewModel.filter.period.icon,
                    isActive: viewModel.filter.period != .all
                ) {
                    let cases = PeriodFilter.allCases
                    let idx = cases.firstIndex(of: viewModel.filter.period) ?? cases.startIndex
                    viewModel.filter.period = cases[(cases.distance(from: cases.startIndex, to: idx) + 1) % cases.count]
                }

                filterCycleButton(
                    title: viewModel.filter.minimumKudos.displayName,
                    icon: viewModel.filter.minimumKudos.icon,
                    isActive: viewModel.filter.minimumKudos != .all
                ) {
                    let cases = KudosFilter.allCases
                    let idx = cases.firstIndex(of: viewModel.filter.minimumKudos) ?? cases.startIndex
                    viewModel.filter.minimumKudos = cases[(cases.distance(from: cases.startIndex, to: idx) + 1) % cases.count]
                }

                filterCycleButton(
                    title: viewModel.filter.duration.displayName,
                    icon: viewModel.filter.duration.icon,
                    isActive: viewModel.filter.duration != .all
                ) {
                    let cases = DurationFilter.allCases
                    let idx = cases.firstIndex(of: viewModel.filter.duration) ?? cases.startIndex
                    viewModel.filter.duration = cases[(cases.distance(from: cases.startIndex, to: idx) + 1) % cases.count]
                }

                if viewModel.filter.isActive {
                    Button {
                        viewModel.resetFilters()
                    } label: {
                        Label("Reset", systemImage: "xmark.circle.fill")
                            .font(.callout)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 50)
            .padding(.vertical, 10)
        }
        .scrollClipDisabled()
    }

    func filterCycleButton(
        title: String,
        icon: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.callout)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? .white : .primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(isActive ? Color.dumpiGreen : Color.white.opacity(0.15), in: Capsule())
        }
        .buttonStyle(FocusableCapsuleButtonStyle())
        .accessibilityLabel(Text("Filter: \(title)", comment: "Accessibility: filter button label"))
        .accessibilityValue(Text(isActive ? String(localized: "Actief", comment: "Accessibility: filter is active") : String(localized: "Inactief", comment: "Accessibility: filter is inactive")))
    }
}
