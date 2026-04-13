import Combine
import CryptoKit
import Foundation

/// Offer to stay on a previously adopted bundled program or take the latest copy from the server catalog (or disk cache of it).
struct BundledProgramUpdateOffer: Identifiable, Equatable {
    var id: String { programId }
    let programId: String
    let programName: String
    let currentAdopted: WorkoutProgram
    let latestFromBundle: WorkoutProgram
}

private struct UserProgramsFile: Codable, Equatable {
    var customPrograms: [WorkoutProgram]
    var bundledOverrides: [String: WorkoutProgram]
    /// Last merged definition the user is “on” for each bundled id (used to detect published catalog changes).
    var bundledAdoptionSnapshots: [String: WorkoutProgram]

    enum CodingKeys: String, CodingKey {
        case customPrograms
        case bundledOverrides
        case bundledAdoptionSnapshots
    }

    init(
        customPrograms: [WorkoutProgram] = [],
        bundledOverrides: [String: WorkoutProgram] = [:],
        bundledAdoptionSnapshots: [String: WorkoutProgram] = [:]
    ) {
        self.customPrograms = customPrograms
        self.bundledOverrides = bundledOverrides
        self.bundledAdoptionSnapshots = bundledAdoptionSnapshots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customPrograms = try c.decodeIfPresent([WorkoutProgram].self, forKey: .customPrograms) ?? []
        bundledOverrides = try c.decodeIfPresent([String: WorkoutProgram].self, forKey: .bundledOverrides) ?? [:]
        bundledAdoptionSnapshots = try c.decodeIfPresent([String: WorkoutProgram].self, forKey: .bundledAdoptionSnapshots) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(customPrograms, forKey: .customPrograms)
        try c.encode(bundledOverrides, forKey: .bundledOverrides)
        try c.encode(bundledAdoptionSnapshots, forKey: .bundledAdoptionSnapshots)
    }
}

@MainActor
final class BundleDataStore: ObservableObject {
    static let shared = BundleDataStore()

    @Published private(set) var workoutPrograms: WorkoutProgramsBundle?
    @Published private(set) var progressBundle: ProgressDataBundle?
    /// Bump when custom programs or bundled overrides change (merged catalog updated).
    @Published private(set) var userProgramsRevision: Int = 0
    /// One bundled program at a time; set when the published catalog differs from the user’s adopted snapshot.
    @Published private(set) var pendingBundledProgramUpdate: BundledProgramUpdateOffer?
    /// Set when the catalog is empty and the Blueprint API URL is not configured, or when a refresh failed before any cache existed.
    @Published private(set) var catalogSyncMessage: String?
    @Published private(set) var isRefreshingCatalog: Bool = false

    private var userProgramsFile: UserProgramsFile = .init()
    private var didLoadUserProgramsFromDisk = false
    private var lastLoggedWorkoutsForBundledUpdates: [LoggedWorkout] = []

    private init() {
        loadIfNeeded()
    }

    func loadIfNeeded() {
        if workoutPrograms == nil {
            loadCachedWorkoutCatalogFromDisk()
        }
        if progressBundle == nil {
            progressBundle = Self.loadJSON(name: "progress_data", as: ProgressDataBundle.self)
        }
        if !didLoadUserProgramsFromDisk {
            loadUserProgramsFromDisk()
            didLoadUserProgramsFromDisk = true
        }
    }

    /// Fetches the published catalog from the Blueprint API when configured; otherwise relies on `Application Support` cache from a prior sync.
    func refreshCatalogFromServer() async {
        loadIfNeeded()
        guard BlueprintAPIConfig.isConfigured else {
            if workoutPrograms == nil {
                catalogSyncMessage =
                    "Workout programs load from the Blueprint API. Set BLUEPRINT_API_URL (Debug uses local defaults), or open the app once after a successful sync to populate the offline cache."
            } else {
                catalogSyncMessage = nil
            }
            return
        }
        isRefreshingCatalog = true
        defer { isRefreshingCatalog = false }
        do {
            let fetched = try await BlueprintCatalogFetcher.fetchWorkoutProgramsBundle()
            workoutPrograms = fetched
            Self.saveCachedWorkoutCatalog(fetched)
            catalogSyncMessage = nil
            userProgramsRevision += 1
            refreshBundledProgramUpdateOffers(programLibrary: UserProgramLibrary.shared)
        } catch {
            if workoutPrograms == nil {
                catalogSyncMessage = error.localizedDescription
            }
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

    /// Call from the root view when `LoggedWorkout` rows change so engagement checks stay current.
    func setLoggedWorkoutsForBundledProgramUpdateScan(_ workouts: [LoggedWorkout]) {
        lastLoggedWorkoutsForBundledUpdates = workouts
    }

    /// When the user adds or removes a **bundled** program from their profile, refresh adoption baselines.
    func noteBundledProgramProfileMembershipChange(programId: String, enabled: Bool) {
        loadIfNeeded()
        guard isBundledProgram(id: programId) else { return }
        if enabled {
            if userProgramsFile.bundledAdoptionSnapshots[programId] == nil,
               let m = mergedPrograms.first(where: { $0.id == programId }) {
                userProgramsFile.bundledAdoptionSnapshots[programId] = m
                persistUserPrograms()
            }
        } else if userProgramsFile.bundledAdoptionSnapshots.removeValue(forKey: programId) != nil {
            persistUserPrograms()
        }
    }

    func refreshBundledProgramUpdateOffers(programLibrary: UserProgramLibrary) {
        loadIfNeeded()
        if pendingBundledProgramUpdate != nil { return }
        guard let basePrograms = workoutPrograms?.programs else { return }
        let merged = mergedPrograms
        var didWriteAdoption = false

        for base in basePrograms {
            let id = base.id
            guard isBundledProgram(id: id) else { continue }
            if hasBundledOverride(programId: id) { continue }
            guard userEngagedWithBundledProgram(
                id: id,
                programName: base.name,
                mergedCatalog: merged,
                loggedWorkouts: lastLoggedWorkoutsForBundledUpdates,
                programLibrary: programLibrary
            ) else { continue }

            if userProgramsFile.bundledAdoptionSnapshots[id] == nil, let m = merged.first(where: { $0.id == id }) {
                userProgramsFile.bundledAdoptionSnapshots[id] = m
                didWriteAdoption = true
            }
            guard let snapshot = userProgramsFile.bundledAdoptionSnapshots[id] else { continue }
            if Self.programFingerprint(base) != Self.programFingerprint(snapshot) {
                pendingBundledProgramUpdate = BundledProgramUpdateOffer(
                    programId: id,
                    programName: base.name,
                    currentAdopted: snapshot,
                    latestFromBundle: base
                )
                if didWriteAdoption { persistUserPrograms() }
                return
            }
        }
        if didWriteAdoption { persistUserPrograms() }
    }

    func resolveBundledProgramUpdateKeepCurrent() {
        guard let offer = pendingBundledProgramUpdate else { return }
        guard isBundledProgram(id: offer.programId) else { return }
        userProgramsFile.bundledOverrides[offer.programId] = offer.currentAdopted
        userProgramsFile.bundledAdoptionSnapshots[offer.programId] = offer.currentAdopted
        pendingBundledProgramUpdate = nil
        persistUserPrograms()
        refreshBundledProgramUpdateOffers(programLibrary: UserProgramLibrary.shared)
    }

    func resolveBundledProgramUpdateUseLatest() {
        guard let offer = pendingBundledProgramUpdate else { return }
        userProgramsFile.bundledOverrides.removeValue(forKey: offer.programId)
        userProgramsFile.bundledAdoptionSnapshots[offer.programId] = offer.latestFromBundle
        pendingBundledProgramUpdate = nil
        persistUserPrograms()
        refreshBundledProgramUpdateOffers(programLibrary: UserProgramLibrary.shared)
    }

    private func userEngagedWithBundledProgram(
        id: String,
        programName: String,
        mergedCatalog: [WorkoutProgram],
        loggedWorkouts: [LoggedWorkout],
        programLibrary: UserProgramLibrary
    ) -> Bool {
        if loggedWorkouts.contains(where: { $0.programId == id }) { return true }
        if loggedWorkouts.contains(where: { $0.programId == nil && $0.programName == programName }) { return true }
        let inProfile = programLibrary.isInLibrary(programId: id, catalog: mergedCatalog)
        if programLibrary.hasCustomLibrarySelection, inProfile { return true }
        return false
    }

    private static func programFingerprint(_ program: WorkoutProgram) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let data = try? enc.encode(program) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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

    private static var appSupportDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("bp-workout", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var catalogCacheURL: URL {
        appSupportDirectory.appendingPathComponent("cached_workout_catalog.json")
    }

    private func loadCachedWorkoutCatalogFromDisk() {
        let url = Self.catalogCacheURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let data = try Data(contentsOf: url)
            workoutPrograms = try JSONDecoder().decode(WorkoutProgramsBundle.self, from: data)
        } catch {
            assertionFailure("Cached catalog decode failed: \(error)")
        }
    }

    private static func saveCachedWorkoutCatalog(_ bundle: WorkoutProgramsBundle) {
        do {
            let data = try JSONEncoder().encode(bundle)
            try data.write(to: catalogCacheURL, options: [.atomic])
        } catch {
            assertionFailure("Cached catalog save failed: \(error)")
        }
    }

    private static var userProgramsURL: URL {
        appSupportDirectory.appendingPathComponent("user_programs.json")
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
