import Combine
import Foundation

private let storageKey = "neil-workout-settings"

@MainActor
final class AppSettings: ObservableObject {
    @Published var filterAnomalies: Bool
    @Published var anomalySensitivity: AnomalySensitivity
    @Published var minReps: Int
    /// When on, bundled programs can be edited from the Programs tab (stored as local overrides).
    @Published var programAdminMode: Bool

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            filterAnomalies = decoded.filterAnomalies
            anomalySensitivity = decoded.anomalySensitivity
            minReps = decoded.minReps
            programAdminMode = decoded.programAdminMode ?? false
        } else {
            filterAnomalies = true
            anomalySensitivity = .medium
            minReps = 5
            programAdminMode = false
        }
    }

    private struct Persisted: Codable {
        var filterAnomalies: Bool
        var anomalySensitivity: AnomalySensitivity
        var minReps: Int
        var programAdminMode: Bool?
    }

    func persist() {
        let p = Persisted(
            filterAnomalies: filterAnomalies,
            anomalySensitivity: anomalySensitivity,
            minReps: minReps,
            programAdminMode: programAdminMode
        )
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func reset() {
        filterAnomalies = true
        anomalySensitivity = .medium
        minReps = 5
        programAdminMode = false
        persist()
    }
}
