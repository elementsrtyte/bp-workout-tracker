import Foundation

struct Exercise: Codable, Hashable, Identifiable {
    var id: String { name }
    let name: String
    let maxWeight: String
    /// Prescribed working sets for this lift; omit in JSON to default to 3.
    let targetSets: Int?
    /// Reps per working set when not AMRAP; omit to infer from load text / history (default 8 in prefill).
    let targetReps: Int?
    /// Exercises sharing the same positive group index are supersetted; omit or null if not in a superset.
    let supersetGroup: Int?
    /// When true, working sets are AMRAP (reps to failure); omit or false for a fixed rep target.
    let isAmrap: Bool?
    /// When true, this line is warm-up / activation only (optional for save warnings).
    let isWarmup: Bool?
    /// Optional free-form notes for this exercise (coaching cues, equipment, etc.).
    let notes: String?

    var prescriptionIsAmrap: Bool { isAmrap == true }
    var prescriptionIsWarmup: Bool { isWarmup == true }

    var trimmedProgramNotes: String? {
        guard let n = notes else { return nil }
        let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// Clamped prescription used for logging UI (1…20).
    var prescribedSets: Int {
        let n = targetSets ?? 3
        return max(1, min(n, 20))
    }

    /// Prescribed rep target for fixed-rep work; nil when AMRAP or not specified in the program.
    var prescribedRepTarget: Int? {
        guard !prescriptionIsAmrap else { return nil }
        guard let r = targetReps else { return nil }
        return max(1, min(r, 100))
    }
}

struct WorkoutDay: Codable, Hashable, Identifiable {
    var id: String { label }
    let label: String
    let exercises: [Exercise]
}

struct WorkoutProgram: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let period: String
    let dateRange: String
    let days: [WorkoutDay]
    let color: String
    let isUserCreated: Bool?
    /// Populated for server catalog programs with a marketplace category.
    let categorySlug: String?
    let categoryTitle: String?

    /// Marketplace accent when the program editor does not expose a custom color.
    static let defaultAccentHex = "#66bfcc"
}

struct CatalogCategory: Codable, Hashable, Identifiable {
    var id: String { slug }
    let slug: String
    let title: String
    let subtitle: String
    let sortOrder: Int
    let iconSfSymbol: String
}

struct ProgramStats: Codable, Hashable {
    let totalPrograms: Int
    let totalMonths: Int
    let totalWorkoutDays: Int
    let dateRange: String
}

struct WorkoutProgramsBundle: Codable {
    let programs: [WorkoutProgram]
    let stats: ProgramStats
    let categories: [CatalogCategory]

    enum CodingKeys: String, CodingKey {
        case programs
        case stats
        case categories
    }

    init(programs: [WorkoutProgram], stats: ProgramStats, categories: [CatalogCategory]) {
        self.programs = programs
        self.stats = stats
        self.categories = categories
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        programs = try c.decode([WorkoutProgram].self, forKey: .programs)
        stats = try c.decode(ProgramStats.self, forKey: .stats)
        categories = try c.decodeIfPresent([CatalogCategory].self, forKey: .categories) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(programs, forKey: .programs)
        try c.encode(stats, forKey: .stats)
        try c.encode(categories, forKey: .categories)
    }
}
