import Foundation
import Observation

@MainActor
@Observable
final class FavoritesStore {
    private(set) var ids: Set<FavoriteID> = []

    func contains(_ id: FavoriteID) -> Bool { ids.contains(id) }

    func toggle(_ id: FavoriteID) {
        if !ids.insert(id).inserted { ids.remove(id) }
    }
}
