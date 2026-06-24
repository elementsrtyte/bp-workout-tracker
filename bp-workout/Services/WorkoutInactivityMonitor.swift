import Foundation
import UserNotifications

/// Reminds the user to end a stale in-progress workout after 30 minutes without edits.
enum WorkoutInactivityMonitor {
    private static let notificationId = "bpworkout.inactivity-reminder"
    static let inactivityThreshold: TimeInterval = 30 * 60

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func scheduleReminderIfNeeded(lastActivity: Date, sessionActive: Bool) {
        cancelReminder()
        guard sessionActive else { return }
        let fire = lastActivity.addingTimeInterval(inactivityThreshold)
        guard fire > Date() else {
            postImmediateReminder()
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Still working out?"
        content.body = "Your workout session has been idle for 30 minutes. Save or discard it if you're done."
        content.sound = .default
        let interval = fire.timeIntervalSinceNow
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let req = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    static func cancelReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
    }

    private static func postImmediateReminder() {
        let content = UNMutableNotificationContent()
        content.title = "Still working out?"
        content.body = "Your workout session has been idle for 30 minutes. Save or discard it if you're done."
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: notificationId,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(req)
    }
}
