import Combine
import Foundation

@MainActor
final class BundleDataStore: ObservableObject {
    static let shared = BundleDataStore()

    @Published private(set) var workoutPrograms: WorkoutProgramsBundle?
    @Published private(set) var progressBundle: ProgressDataBundle?

    private init() {
        loadIfNeeded()
    }

    func loadIfNeeded() {
        if workoutPrograms != nil, progressBundle != nil { return }
        workoutPrograms = Self.loadJSON(name: "workout_programs", as: WorkoutProgramsBundle.self)
        progressBundle = Self.loadJSON(name: "progress_data", as: ProgressDataBundle.self)
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
}
