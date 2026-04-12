import Foundation

struct LogWorkoutTemplate: Identifiable, Hashable {
    var id: String { "\(programName ?? "nil")-\(dayLabel ?? "nil")" }
    let programName: String?
    let dayLabel: String?
}
