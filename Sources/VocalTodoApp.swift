import SwiftUI
import SwiftData
import UserNotifications

@main
struct VocalTodoApp: App {
    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup { ContentView() }
            .modelContainer(for: TodoItem.self) // stockage local sur l'iPhone
    }
}

/// Affiche aussi la notification si l'app est ouverte.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@Model
final class TodoItem {
    var id: UUID = UUID()
    var title: String = ""
    var details: String = ""
    var dueDate: Date?
    var isDone: Bool = false
    var calendarEventID: String?
    var createdAt: Date = Date()

    init(title: String, details: String = "", dueDate: Date? = nil) {
        self.title = title
        self.details = details
        self.dueDate = dueDate
    }
}

/// Notifications locales : elles sonnent même téléphone verrouillé et app fermée.
enum Reminders {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func schedule(_ t: TodoItem) {
        cancel(t)
        guard let due = t.dueDate, due > Date(), !t.isDone else { return }
        let content = UNMutableNotificationContent()
        content.title = t.title
        content.body = t.details
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: t.id.uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    static func cancel(_ t: TodoItem) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [t.id.uuidString])
    }
}
