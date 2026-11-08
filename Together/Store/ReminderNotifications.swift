import Foundation
import UserNotifications

/// A local notification for one of *my* task reminders. One per task: the task id is the identifier, so
/// scheduling again replaces it and an edit, completion or deletion can never leave a duplicate.
struct LocalReminder: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    var fireAt: Date
}

/// Where the store sends reminder changes. Tests use a fake; the app uses `UserNotificationReminders`.
@MainActor
protocol ReminderNotifying: AnyObject {
    /// Adds or replaces the notification with this id.
    func schedule(_ reminder: LocalReminder)
    func cancel(id: String)
}

/// Does nothing — previews and the default for stores that don't need notifications.
@MainActor
final class NoReminderNotifications: ReminderNotifying {
    func schedule(_ reminder: LocalReminder) {}
    func cancel(id: String) {}
}

/// `UNUserNotificationCenter`-backed reminders. Permission is asked the first time a reminder is scheduled,
/// not at launch.
@MainActor
final class UserNotificationReminders: ReminderNotifying {
    private let center: UNUserNotificationCenter
    /// The latest request per id; an older async schedule that finishes late is dropped.
    private var latest: [String: UUID] = [:]

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func schedule(_ reminder: LocalReminder) {
        let token = UUID()
        latest[reminder.id] = token
        Task {
            guard await authorized(), latest[reminder.id] == token else { return }
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireAt)
            let request = UNNotificationRequest(
                identifier: reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    func cancel(id: String) {
        latest[id] = nil
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    private func authorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }
}
