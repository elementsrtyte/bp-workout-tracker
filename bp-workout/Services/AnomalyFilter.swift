import Foundation

enum AnomalySensitivity: String, CaseIterable, Codable, Sendable {
    case low, medium, high
}

struct FilteredEntry: Hashable {
    var entry: ProgressEntry
    var isAnomaly: Bool
    var anomalyReason: String?
}

enum AnomalyFilter {
    private static let kMap: [AnomalySensitivity: Double] = [
        .low: 3.0,
        .medium: 2.0,
        .high: 1.5,
    ]

    private static func quantile(sorted: [Double], q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let pos = Double(sorted.count - 1) * q
        let base = Int(floor(pos))
        let rest = pos - Double(base)
        if base + 1 < sorted.count {
            return sorted[base] + rest * (sorted[base + 1] - sorted[base])
        }
        return sorted[base]
    }

    private static func median(sorted: [Double]) -> Double {
        quantile(sorted: sorted, q: 0.5)
    }

    static func filterAnomalies(entries: [ProgressEntry], sensitivity: AnomalySensitivity) -> [FilteredEntry] {
        guard entries.count >= 4 else {
            return entries.map { FilteredEntry(entry: $0, isAnomaly: false, anomalyReason: nil) }
        }

        let weights = entries.map(\.weight)
        let sorted = weights.sorted()
        let q1 = quantile(sorted: sorted, q: 0.25)
        let q3 = quantile(sorted: sorted, q: 0.75)
        let iqr = q3 - q1
        let k = kMap[sensitivity] ?? 2.0
        let lower = q1 - k * iqr
        let upper = q3 + k * iqr
        let med = median(sorted: sorted)

        return entries.enumerated().map { i, entry in
            let w = entry.weight

            if w < lower || w > upper {
                return FilteredEntry(
                    entry: entry,
                    isAnomaly: true,
                    anomalyReason: "Outside IQR fence [\(lower.formatted(.number.precision(.fractionLength(1)))), \(upper.formatted(.number.precision(.fractionLength(1))))] lbs"
                )
            }

            var neighbors: [Double] = []
            if i > 0 { neighbors.append(entries[i - 1].weight) }
            if i < entries.count - 1 { neighbors.append(entries[i + 1].weight) }
            if !neighbors.isEmpty {
                let neighborMedian = neighbors.reduce(0, +) / Double(neighbors.count)
                if neighborMedian > 0, (w > neighborMedian * 4 || w < neighborMedian / 4) {
                    if w > med * 3 || w < med / 3 {
                        return FilteredEntry(
                            entry: entry,
                            isAnomaly: true,
                            anomalyReason: "Implausible jump: \(w) lbs vs neighbors avg \(neighborMedian.formatted(.number.precision(.fractionLength(1)))) lbs"
                        )
                    }
                }
            }

            return FilteredEntry(entry: entry, isAnomaly: false, anomalyReason: nil)
        }
    }

    static func getCleanEntries(
        entries: [ProgressEntry],
        filterEnabled: Bool,
        sensitivity: AnomalySensitivity,
        minReps: Int = 0
    ) -> [ProgressEntry] {
        let repFiltered = minReps > 0 ? entries.filter { $0.reps >= minReps } : entries
        guard filterEnabled else { return repFiltered }
        return filterAnomalies(entries: repFiltered, sensitivity: sensitivity).filter { !$0.isAnomaly }.map(\.entry)
    }

    static func countAnomalies(entries: [ProgressEntry], sensitivity: AnomalySensitivity) -> Int {
        guard entries.count >= 4 else { return 0 }
        return filterAnomalies(entries: entries, sensitivity: sensitivity).filter(\.isAnomaly).count
    }
}
