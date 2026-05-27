import SwiftUI

extension SearchView {
    static let categories: [(name: LocalizedStringKey, icon: String, query: String)] = [
        ("Dashcam", "car.fill", "dashcam"),
        ("Fail", "figure.fall", "fail"),
        ("Compilatie", "film.stack", "compilatie"),
        ("Politie", "shield.lefthalf.filled", "politie"),
        ("Motor", "motorcycle", "motor"),
        ("Schaatsen", "figure.skating", "schaatsen"),
        ("Voetbal", "sportscourt", "voetbal"),
        ("Dieren", "pawprint.fill", "dieren"),
        ("Muziek", "music.note", "muziek"),
        ("Vuurwerk", "sparkles", "vuurwerk"),
        ("Karma", "arrow.uturn.backward.circle", "karma"),
        ("Fietsen", "bicycle", "fietsen"),
    ]

    func suggestionsView(_ viewModel: SearchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 40) {
            if !repository.searchHistory.isEmpty {
                recentSearchesSection(viewModel)
                    .focusSection()
            }

            let tags = repository.popularTags
            if !tags.isEmpty {
                popularTagsSection(tags, viewModel: viewModel)
                    .focusSection()
            }

            categoriesSection(viewModel)
                .focusSection()
        }
        .padding(.vertical, 30)
    }

    func recentSearchesSection(_ viewModel: SearchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent gezocht", comment: "Recently searched section header")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Button(String(localized: "Wis alles", comment: "Clear all recent searches button")) {
                    repository.clearSearchHistory()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Wis alle recente zoekopdrachten", comment: "Accessibility: clear all recent searches"))
            }
            .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(repository.searchHistory) { entry in
                        Button {
                            viewModel.searchQuery = entry.query
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                                Text(entry.query)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.card)
                        .accessibilityLabel(Text("Recente zoekopdracht: \(entry.query)", comment: "Accessibility: recent search button"))
                        .contextMenu {
                            Button(String(localized: "Verwijder", comment: "Delete context menu action"), role: .destructive) {
                                repository.deleteSearchEntry(entry)
                            }
                        }
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
        }
    }

    func popularTagsSection(_ tags: [String], viewModel: SearchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Populair", comment: "Popular tags section header")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            viewModel.searchQuery = tag
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "flame.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .accessibilityHidden(true)
                                Text(tag.capitalized)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.card)
                        .accessibilityLabel(Text("Populaire zoekopdracht: \(tag.capitalized)", comment: "Accessibility: popular tag button"))
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 10)
            }
            .scrollClipDisabled()
        }
    }

    func categoriesSection(_ viewModel: SearchViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Categorieën", comment: "Categories section header")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 50)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 30),
                    GridItem(.flexible(), spacing: 30),
                    GridItem(.flexible(), spacing: 30),
                    GridItem(.flexible(), spacing: 30),
                ],
                spacing: 20
            ) {
                ForEach(Self.categories, id: \.query) { category in
                    Button {
                        viewModel.searchQuery = category.query
                    } label: {
                        HStack(spacing: 20) {
                            Image(systemName: category.icon)
                                .font(.body)
                                .frame(width: 40)
                                .accessibilityHidden(true)
                            Text(category.name)
                                .font(.callout)
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                    .buttonStyle(.card)
                    .accessibilityLabel(Text("Categorie: ", comment: "Accessibility: search category button prefix") + Text(category.name))
                }
            }
            .padding(.horizontal, 50)
        }
    }
}
