import Foundation

// MARK: - LLM JSON (decodable)

private struct LLMImportDay: Codable {
    var label: String?
    var exercises: [LLMImportExercise]?
}

private struct LLMImportExercise: Codable {
    var name: String?
    var maxWeight: String?
    var targetSets: Int?
    var targetReps: Int?
    var supersetGroup: Int?
    var isAmrap: Bool?
    var isWarmup: Bool?
    var notes: String?
}

private struct LLMImportProgram: Codable {
    var name: String?
    var subtitle: String?
    var days: [LLMImportDay]?
}

private struct LLMHistoricalSet: Codable {
    var weight: Double?
    var reps: Int?
}

private struct LLMHistoricalExercise: Codable {
    var name: String?
    var prescribedName: String?
    var sets: [LLMHistoricalSet]?
}

private struct LLMHistoricalWorkout: Codable {
    var date: String?
    var dayLabel: String?
    var notes: String?
    var exercises: [LLMHistoricalExercise]?
}

private struct ImportProgramAPIResponse: Codable {
    let program: LLMImportProgram
    let historicalWorkouts: [LLMHistoricalWorkout]?
}

private struct ImportProgramRequest: Encodable {
    let text: String
}

private enum ImportDateParsers {
    private static let ymd: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        let head = String(raw.prefix(10))
        if let d = ymd.date(from: head) { return d }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [
            .withFullDate, .withTime, .withDashSeparatorInDate,
            .withColonSeparatorInTime,
        ]
        return iso.date(from: raw)
    }
}

// MARK: - Public

enum OpenAIProgramImportService {
    enum ImportError: LocalizedError {
        case emptyPaste
        case decode(String)
        case noTrainingContent

        var errorDescription: String? {
            switch self {
            case .emptyPaste: return "Paste a workout description first."
            case .decode(let m): return m
            case .noTrainingContent: return "Couldn’t find any program days or exercises to import."
            }
        }
    }

    private static let maxHistoricalSessions = 250

    /// Parses free-form text via the Blueprint API (`POST /v1/imports/programs` with JSON `{ "text": "…" }`).
    static func importResult(fromPastedText text: String) async throws -> ProgramImportResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyPaste }
        guard BlueprintAPIConfig.isConfigured else { throw BlueprintAPIError.notConfigured }

        let token = try await SupabaseSessionManager.shared.accessTokenForAPI()
        let data = try await BlueprintAPIClient.post(
            path: "/v1/imports/programs",
            body: ImportProgramRequest(text: trimmed),
            accessToken: token
        )
        return try decodeImportResponse(data)
    }

    /// Plain-text body (`Content-Type: text/plain`) on `POST /v1/imports/programs`.
    static func importResult(fromPlainTextBody text: String) async throws -> ProgramImportResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyPaste }
        guard BlueprintAPIConfig.isConfigured else { throw BlueprintAPIError.notConfigured }

        let token = try await SupabaseSessionManager.shared.accessTokenForAPI()
        let data = try await BlueprintAPIClient.postPlainText(
            path: "/v1/imports/programs",
            text: trimmed,
            accessToken: token
        )
        return try decodeImportResponse(data)
    }

    private static func decodeImportResponse(_ data: Data) throws -> ProgramImportResult {
        let decoded = try JSONDecoder().decode(ImportProgramAPIResponse.self, from: data)
        let historical = mapHistoricalWorkouts(decoded.historicalWorkouts ?? [])
        var program = try mapToWorkoutProgram(decoded.program)
        if program.days.isEmpty, !historical.isEmpty {
            program = try synthesizeProgram(from: historical, base: program)
        }
        guard !program.days.isEmpty else { throw ImportError.noTrainingContent }
        return ProgramImportResult(program: program, historicalWorkouts: historical)
    }

    private static func mapHistoricalWorkouts(_ rows: [LLMHistoricalWorkout]) -> [HistoricalWorkoutDraft] {
        var out: [HistoricalWorkoutDraft] = []
        for row in rows.prefix(maxHistoricalSessions) {
            guard let date = ImportDateParsers.parse(row.date) else { continue }
            var exDrafts: [HistoricalExerciseDraft] = []
            for ex in row.exercises ?? [] {
                let name = ex.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !name.isEmpty else { continue }
                let prescribed = ex.prescribedName?.trimmingCharacters(in: .whitespacesAndNewlines)
                let prescribedName = (prescribed?.isEmpty == false) ? prescribed : nil
                var setDrafts: [HistoricalSetDraft] = []
                for s in ex.sets ?? [] {
                    let r = s.reps ?? 0
                    guard r > 0 else { continue }
                    let w = max(0, s.weight ?? 0)
                    setDrafts.append(HistoricalSetDraft(weight: w.isFinite ? w : 0, reps: min(200, r)))
                }
                guard !setDrafts.isEmpty else { continue }
                exDrafts.append(
                    HistoricalExerciseDraft(name: name, prescribedName: prescribedName, sets: setDrafts)
                )
            }
            guard !exDrafts.isEmpty else { continue }
            let notes = row.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            let dayLabel = row.dayLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(
                HistoricalWorkoutDraft(
                    date: date,
                    dayLabel: (dayLabel?.isEmpty == false) ? dayLabel : nil,
                    notes: (notes?.isEmpty == false) ? notes : nil,
                    exercises: exDrafts
                )
            )
        }
        return out
    }

    /// If the model returned no template days but we have history, build a minimal single-day template.
    private static func synthesizeProgram(
        from historical: [HistoricalWorkoutDraft],
        base: WorkoutProgram
    ) throws -> WorkoutProgram {
        var names: [String] = []
        var seen = Set<String>()
        for w in historical {
            for ex in w.exercises {
                let k = ExerciseNameNormalizer.key(ex.name)
                if seen.insert(k).inserted {
                    names.append(ex.name)
                }
                if names.count >= 18 { break }
            }
            if names.count >= 18 { break }
        }
        guard !names.isEmpty else { throw ImportError.noTrainingContent }
        let exercises = names.map {
            Exercise(
                name: $0,
                maxWeight: "",
                targetSets: 3,
                targetReps: nil,
                supersetGroup: nil,
                isAmrap: nil,
                isWarmup: nil,
                notes: nil
            )
        }
        let day = WorkoutDay(label: "Day 1", exercises: exercises)
        let subtitle = base.subtitle.isEmpty
            ? "Template inferred from imported workout history."
            : base.subtitle
        return WorkoutProgram(
            id: base.id,
            name: base.name,
            subtitle: subtitle,
            period: base.period,
            dateRange: base.dateRange,
            days: [day],
            color: base.color,
            isUserCreated: base.isUserCreated
        )
    }

    private static func mapToWorkoutProgram(_ dto: LLMImportProgram) throws -> WorkoutProgram {
        var name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty { name = "Imported program" }

        var days: [WorkoutDay] = []
        for day in dto.days ?? [] {
            let label = day.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let dayLabel = label.isEmpty ? "Day \(days.count + 1)" : label

            var exercises: [Exercise] = []
            for ex in day.exercises ?? [] {
                let exName = ex.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !exName.isEmpty else { continue }

                let sets = ex.targetSets.map { max(1, min(20, $0)) } ?? 3
                let repT = ex.targetReps.map { max(1, min(100, $0)) }
                let sg = ex.supersetGroup.flatMap { (1 ... 6).contains($0) ? $0 : nil }
                let mw = ex.maxWeight?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let note = ex.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                exercises.append(
                    Exercise(
                        name: exName,
                        maxWeight: mw,
                        targetSets: sets,
                        targetReps: ex.isAmrap == true ? nil : repT,
                        supersetGroup: sg,
                        isAmrap: ex.isAmrap == true ? true : nil,
                        isWarmup: ex.isWarmup == true ? true : nil,
                        notes: (note?.isEmpty == false) ? note : nil
                    )
                )
            }
            guard !exercises.isEmpty else { continue }
            days.append(WorkoutDay(label: dayLabel, exercises: exercises))
        }

        let subtitle = dto.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return WorkoutProgram(
            id: "user-\(UUID().uuidString)",
            name: name,
            subtitle: subtitle,
            period: "",
            dateRange: "",
            days: days,
            color: WorkoutProgram.defaultAccentHex,
            isUserCreated: true
        )
    }
}
