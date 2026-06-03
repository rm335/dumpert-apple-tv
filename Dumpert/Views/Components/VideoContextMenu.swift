import SwiftUI

/// Shared context menu for video/photo items across all section views.
/// Provides watch toggle and category management actions.
struct VideoContextMenuModifier: ViewModifier {
    let item: MediaItem
    let repository: VideoRepository
    @Binding var toastMessage: String?
    var currentCategory: VideoCategory?

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(repository.isWatched(item.id) ? String(localized: "Markeer als onbekeken", comment: "Context menu: mark as unwatched") : String(localized: "Markeer als bekeken", comment: "Context menu: mark as watched")) {
                let wasWatched = repository.isWatched(item.id)
                repository.toggleWatched(videoId: item.id)
                toastMessage = wasWatched
                    ? String(localized: "Gemarkeerd als onbekeken", comment: "Toast: video marked as unwatched")
                    : String(localized: "Gemarkeerd als bekeken", comment: "Toast: video marked as watched")
            }

            if let currentCategory, currentCategory.supportsCuration {
                Button(String(localized: "Verwijder uit \(currentCategory.displayName)", comment: "Context menu: remove from category")) {
                    repository.removeFromCategory(videoId: item.id, category: currentCategory)
                    toastMessage = String(localized: "Verwijderd uit \(currentCategory.displayName)", comment: "Toast: removed from category")
                }
            }

            ForEach(VideoCategory.allCases.filter { $0 != currentCategory && $0.supportsCuration }) { category in
                Button(String(localized: "Voeg toe aan \(category.displayName)", comment: "Context menu: add to category")) {
                    repository.addToCategory(videoId: item.id, category: category)
                    toastMessage = String(localized: "Toegevoegd aan \(category.displayName)", comment: "Toast: added to category")
                }
            }
        }
    }
}

extension View {
    func videoContextMenu(
        item: MediaItem,
        repository: VideoRepository,
        toastMessage: Binding<String?>,
        currentCategory: VideoCategory? = nil
    ) -> some View {
        modifier(VideoContextMenuModifier(
            item: item,
            repository: repository,
            toastMessage: toastMessage,
            currentCategory: currentCategory
        ))
    }
}
