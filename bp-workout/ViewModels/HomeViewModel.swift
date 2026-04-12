import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var activeProgramId: String = ""
    @Published var dayIndex: Int = 0
    @Published var logTemplate: LogWorkoutTemplate?

    private let bundle: BundleDataStore

    init(bundle: BundleDataStore = .shared) {
        self.bundle = bundle
    }

    var programs: [WorkoutProgram] {
        bundle.workoutPrograms?.programs ?? []
    }

    var stats: ProgramStats? {
        bundle.workoutPrograms?.stats
    }

    var activeProgram: WorkoutProgram? {
        programs.first { $0.id == activeProgramId }
    }

    func onAppear() {
        bundle.loadIfNeeded()
        if activeProgramId.isEmpty, let first = programs.first {
            activeProgramId = first.id
        }
    }

    func selectProgram(id: String) {
        activeProgramId = id
        dayIndex = 0
    }

    func beginLogCurrentDay(programName: String, dayLabel: String) {
        logTemplate = LogWorkoutTemplate(programName: programName, dayLabel: dayLabel)
    }
}
