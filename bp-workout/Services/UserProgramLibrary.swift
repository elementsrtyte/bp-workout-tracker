import Combine
import Foundation

/// Programs the user has added to their profile (Workout tab picker). When nothing is stored yet, every catalog program is treated as included.
@MainActor
final class UserProgramLibrary: ObservableObject {
    static let shared = UserProgramLibrary()

    @Published private(set) var updateCounter: Int = 0

    private let defaultsKey = "profile.libraryProgramIds"
    private let activeProgramDefaultsKey = "workoutHub.activeProgramId"

    private init() {}

    func idsInLibrary(catalogIds: [String]) -> Set<String> {
        let catalog = Set(catalogIds)
        if UserDefaults.standard.object(forKey: defaultsKey) == nil {
            return catalog
        }
        let stored = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
        return stored.intersection(catalog)
    }

    func isInLibrary(programId: String, catalog: [WorkoutProgram]) -> Bool {
        let ids = catalog.map(\.id)
        return idsInLibrary(catalogIds: ids).contains(programId)
    }

    func setProgramInLibrary(_ programId: String, enabled: Bool, catalog: [WorkoutProgram]) {
        let catalogIds = catalog.map(\.id)
        var next = idsInLibrary(catalogIds: catalogIds)
        if enabled {
            next.insert(programId)
        } else {
            next.remove(programId)
        }
        UserDefaults.standard.set(Array(next), forKey: defaultsKey)
        updateCounter += 1
        reconcileStoredActiveProgram(catalog: catalog)
    }

    /// Keeps `workoutHub.activeProgramId` pointing at a program still in the library (or clears it).
    private func reconcileStoredActiveProgram(catalog: [WorkoutProgram]) {
        let inLib = programsInProfile(from: catalog)
        let d = UserDefaults.standard
        if inLib.isEmpty {
            d.set("", forKey: activeProgramDefaultsKey)
            return
        }
        if let saved = d.string(forKey: activeProgramDefaultsKey), !saved.isEmpty,
           inLib.contains(where: { $0.id == saved }) {
            return
        }
        d.set(inLib[0].id, forKey: activeProgramDefaultsKey)
    }

    func programsInProfile(from catalog: [WorkoutProgram]) -> [WorkoutProgram] {
        let allowed = idsInLibrary(catalogIds: catalog.map(\.id))
        return catalog.filter { allowed.contains($0.id) }
    }
}
