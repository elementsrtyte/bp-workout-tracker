import Foundation

/// Local, offline-friendly replacement ideas: catalog names ranked by token overlap with the prescribed lift.
enum ExerciseSubstitutionSuggestions {
    /// Union of static list + every exercise name from merged programs.
    static func candidatePool(catalogNames: [String]) -> [String] {
        var set = Set(CommonExerciseNames.all.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        for n in catalogNames {
            let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { set.insert(t) }
        }
        return Array(set).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func localSuggestions(prescribedName: String, catalogNames: [String], limit: Int = 14) -> [String] {
        let prescribed = prescribedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prescribed.isEmpty else { return [] }
        let lower = prescribed.lowercased()
        let tokens = significantTokens(lower)
        let pool = candidatePool(catalogNames: catalogNames).filter { $0.caseInsensitiveCompare(prescribed) != .orderedSame }

        func score(_ candidate: String) -> Int {
            let c = candidate.lowercased()
            var s = 0
            if c.hasPrefix(lower) { s += 8 }
            for t in tokens where t.count > 2 {
                if c.contains(t) { s += 3 }
            }
            if tokens.count >= 2 {
                let hit = tokens.filter { c.contains($0) }.count
                if hit >= 2 { s += 4 }
            }
            return s
        }

        let ranked = pool.map { ($0, score($0)) }.sorted { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            return a.0.localizedCaseInsensitiveCompare(b.0) == .orderedAscending
        }
        let strong = ranked.filter { $0.1 > 0 }.map(\.0)
        if !strong.isEmpty { return Array(strong.prefix(limit)) }
        let first = lower.first.map { String($0) } ?? ""
        let byLetter = pool.filter { !$0.isEmpty && $0.lowercased().first.map { String($0) } == first }
        if byLetter.count >= 4 { return Array(byLetter.prefix(limit)) }
        return Array(pool.prefix(limit))
    }

    private static func significantTokens(_ lowercasedPrescribed: String) -> [String] {
        let parts = lowercasedPrescribed.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return parts.map { String($0) }.filter { !$0.isEmpty }
    }
}
