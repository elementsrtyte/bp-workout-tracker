import Foundation
import UserNotifications

enum RestTimerNotificationScheduler {
    private static let pendingId = "bpworkout.rest-between-sets"

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func scheduleRestComplete(after seconds: TimeInterval) {
        cancelScheduled()
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time for your next set."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let req = UNNotificationRequest(identifier: pendingId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    static func cancelScheduled() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [pendingId])
    }
}
