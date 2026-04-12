import Combine
import Foundation

private let storageKey = "neil-workout-settings"

@MainActor
final class AppSettings: ObservableObject {
    @Published var filterAnomalies: Bool
    @Published var anomalySensitivity: AnomalySensitivity
    @Published var minReps: Int

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(Persisted.self, from: data) {
            filterAnomalies = decoded.filterAnomalies
            anomalySensitivity = decoded.anomalySensitivity
            minReps = decoded.minReps
        } else {
            filterAnomalies = true
            anomalySensitivity = .medium
            minReps = 5
        }
    }

    private struct Persisted: Codable {
        var filterAnomalies: Bool
        var anomalySensitivity: AnomalySensitivity
        var minReps: Int
    }

    func persist() {
        let p = Persisted(filterAnomalies: filterAnomalies, anomalySensitivity: anomalySensitivity, minReps: minReps)
        if let data = try? JSONEncoder().encode(p) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    func reset() {
        filterAnomalies = true
        anomalySensitivity = .medium
        minReps = 5
        persist()
    }
}
