import Combine
import Foundation

private struct UserProgramsFile: Codable, Equatable {
    var customPrograms: [WorkoutProgram]
    var bundledOverrides: [String: WorkoutProgram]
}

@MainActor
final class BundleDataStore: ObservableObject {
    static let shared = BundleDataStore()

    @Published private(set) var workoutPrograms: WorkoutProgramsBundle?
    @Published private(set) var progressBundle: ProgressDataBundle?
    /// Bump when custom programs or bundled overrides change (merged catalog updated).
    @Published private(set) var userProgramsRevision: Int = 0

    private var userProgramsFile: UserProgramsFile = .init(customPrograms: [], bundledOverrides: [:])
    private var didLoadUserProgramsFromDisk = false

    private init() {
        loadIfNeeded()
    }

    func loadIfNeeded() {
        if workoutPrograms == nil {
            workoutPrograms = Self.loadJSON(name: "workout_programs", as: WorkoutProgramsBundle.self)
        }
        if progressBundle == nil {
            progressBundle = Self.loadJSON(name: "progress_data", as: ProgressDataBundle.self)
        }
        if !didLoadUserProgramsFromDisk {
            loadUserProgramsFromDisk()
            didLoadUserProgramsFromDisk = true
        }
    }

    func isPersistedCustomProgram(id: String) -> Bool {
        userProgramsFile.customPrograms.contains { $0.id == id }
    }

    /// Bundle JSON programs plus local custom programs and admin overrides.
    var mergedPrograms: [WorkoutProgram] {
        let base = workoutPrograms?.programs ?? []
        return Self.mergeCatalog(
            bundlePrograms: base,
            overrides: userProgramsFile.bundledOverrides,
            customPrograms: userProgramsFile.customPrograms
        )
    }

    var bundledProgramIds: Set<String> {
        Set((workoutPrograms?.programs ?? []).map(\.id))
    }

    func isBundledProgram(id: String) -> Bool {
        bundledProgramIds.contains(id)
    }

    func hasBundledOverride(programId: String) -> Bool {
        userProgramsFile.bundledOverrides[programId] != nil
    }

    func upsertCustomProgram(_ program: WorkoutProgram) {
        if let i = userProgramsFile.customPrograms.firstIndex(where: { $0.id == program.id }) {
            userProgramsFile.customPrograms[i] = program
        } else {
            userProgramsFile.customPrograms.append(program)
        }
        persistUserPrograms()
    }

    func deleteCustomProgram(id: String) {
        userProgramsFile.customPrograms.removeAll { $0.id == id }
        persistUserPrograms()
    }

    func setBundledOverride(_ program: WorkoutProgram) {
        guard isBundledProgram(id: program.id) else { return }
        userProgramsFile.bundledOverrides[program.id] = program
        persistUserPrograms()
    }

    func removeBundledOverride(programId: String) {
        userProgramsFile.bundledOverrides.removeValue(forKey: programId)
        persistUserPrograms()
    }

    private func persistUserPrograms() {
        saveUserProgramsToDisk()
        userProgramsRevision += 1
    }

    private static func mergeCatalog(
        bundlePrograms: [WorkoutProgram],
        overrides: [String: WorkoutProgram],
        customPrograms: [WorkoutProgram]
    ) -> [WorkoutProgram] {
        let bundledIds = Set(bundlePrograms.map(\.id))
        var result: [WorkoutProgram] = []
        for p in bundlePrograms {
            result.append(overrides[p.id] ?? p)
        }
        for p in customPrograms where !bundledIds.contains(p.id) {
            result.append(p)
        }
        return result
    }

    private static func loadJSON<T: Decodable>(name: String, as type: T.Type) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            assertionFailure("Missing bundle resource: \(name).json")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            assertionFailure("Decode failed: \(error)")
            return nil
        }
    }

    private static var userProgramsURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("bp-workout", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("user_programs.json")
    }

    private func loadUserProgramsFromDisk() {
        let url = Self.userProgramsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            userProgramsFile = try JSONDecoder().decode(UserProgramsFile.self, from: data)
        } catch {
            assertionFailure("User programs decode failed: \(error)")
        }
    }

    private func saveUserProgramsToDisk() {
        do {
            let data = try JSONEncoder().encode(userProgramsFile)
            try data.write(to: Self.userProgramsURL, options: [.atomic])
        } catch {
            assertionFailure("User programs save failed: \(error)")
        }
    }
}
