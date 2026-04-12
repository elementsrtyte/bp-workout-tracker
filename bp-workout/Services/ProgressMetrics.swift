import Foundation

enum TrendDirection {
    case up, down, flat
}

enum ProgressMetrics {
    static func trend(entries: [ProgressEntry]) -> TrendDirection {
        guard entries.count >= 2 else { return .flat }
        let n = entries.count
        let head = Array(entries.prefix(min(3, n)))
        let tail = Array(entries.suffix(min(3, n)))
        let avgFirst = head.map(\.weight).reduce(0, +) / Double(head.count)
        let avgLast = tail.map(\.weight).reduce(0, +) / Double(tail.count)
        guard avgFirst > 0 else { return .flat }
        let delta = (avgLast - avgFirst) / avgFirst * 100
        if delta > 5 { return .up }
        if delta < -5 { return .down }
        return .flat
    }

    static func pctChange(entries: [ProgressEntry]) -> Int {
        guard let first = entries.first, let last = entries.last, first.weight != 0 else { return 0 }
        return Int(round((last.weight - first.weight) / first.weight * 100))
    }

    static func volumePctChange(entries: [ProgressEntry]) -> Int {
        guard let first = entries.first, let last = entries.last else { return 0 }
        let v0 = first.weight * Double(first.reps)
        let v1 = last.weight * Double(last.reps)
        guard v0 != 0 else { return 0 }
        return Int(round((v1 - v0) / v0 * 100))
    }

    struct RepBucket: Identifiable {
        var id: String { label }
        let label: String
        let min: Int
        let max: Int
        let colorHex: String
        let description: String
    }

    static let repBuckets: [RepBucket] = [
        .init(label: "1–4", min: 1, max: 4, colorHex: "#c0504d", description: "Strength"),
        .init(label: "5–8", min: 5, max: 8, colorHex: "#d4a843", description: "Power"),
        .init(label: "9–12", min: 9, max: 12, colorHex: "#3ecf8e", description: "Hypertrophy"),
        .init(label: "13+", min: 13, max: 999, colorHex: "#c496ff", description: "Endurance"),
    ]

    static func repRangeCounts(entries: [ProgressEntry]) -> [(bucket: RepBucket, count: Int)] {
        var counts: [String: Int] = [:]
        for b in repBuckets {
            counts[b.label] = 0
        }
        for e in entries {
            let r = e.maxReps > 0 ? e.maxReps : e.reps
            if let b = repBuckets.first(where: { r >= $0.min && r <= $0.max }) {
                counts[b.label, default: 0] += 1
            }
        }
        return repBuckets.map { ($0, counts[$0.label] ?? 0) }
    }

    static func parseChartDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
