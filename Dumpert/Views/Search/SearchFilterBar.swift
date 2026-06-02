import SwiftUI

extension SearchView {
    func filterBar(_ viewModel: SearchViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                filterMenu(
                    title: viewModel.filter.mediaType.displayName,
                    icon: viewModel.filter.mediaType.icon,
                    isActive: viewModel.filter.mediaType != .all,
                    options: MediaTypeFilter.allCases,
                    selection: viewModel.filter.mediaType
                ) { viewModel.filter.mediaType = $0 }

                filterMenu(
                    title: viewModel.filter.period.displayName,
                    icon: viewModel.filter.period.icon,
                    isActive: viewModel.filter.period != .all,
                    options: PeriodFilter.allCases,
                    selection: viewModel.filter.period
                ) { viewModel.filter.period = $0 }

                filterMenu(
                    title: viewModel.filter.minimumKudos.displayName,
                    icon: viewModel.filter.minimumKudos.icon,
                    isActive: viewModel.filter.minimumKudos != .all,
                    options: KudosFilter.allCases,
                    selection: viewModel.filter.minimumKudos
                ) { viewModel.filter.minimumKudos = $0 }

                filterMenu(
                    title: viewModel.filter.duration.displayName,
                    icon: viewModel.filter.duration.icon,
                    isActive: viewModel.filter.duration != .all,
                    options: DurationFilter.allCases,
                    selection: viewModel.filter.duration
                ) { viewModel.filter.duration = $0 }

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

    /// A single refinement control. Replaces the old blind "cycle button" with a
    /// `Menu` so every option is visible on open and the active one is checked —
    /// the Launchpad's job is to *clarify* intent, not hide it behind guesswork.
    func filterMenu<T: FilterOption>(
        title: String,
        icon: String,
        isActive: Bool,
        options: [T],
        selection: T,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    onSelect(option)
                } label: {
                    if option == selection {
                        Label(option.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.displayName)
                    }
                }
            }
        } label: {
            Label(title, systemImage: icon)
                .font(.callout)
                .fontWeight(isActive ? .semibold : .regular)
                .foregroundStyle(isActive ? .white : .primary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(isActive ? Color.dumpiGreen : Color.white.opacity(0.15), in: Capsule())
        }
        .accessibilityLabel(Text("Filter: \(title)", comment: "Accessibility: filter button label"))
        .accessibilityValue(Text(isActive ? String(localized: "Actief", comment: "Accessibility: filter is active") : String(localized: "Inactief", comment: "Accessibility: filter is inactive")))
    }
}
