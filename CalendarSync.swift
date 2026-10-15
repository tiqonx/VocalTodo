import SwiftUI
import EventKit

/// Écrit les tâches datées dans l'agenda iOS choisi (ex. ton agenda Google).
/// iOS se charge ensuite de la synchronisation avec Google.
final class CalendarSync: ObservableObject {
    static let shared = CalendarSync()
    private let store = EKEventStore()

    @Published var calendars: [EKCalendar] = []
    @Published var accessGranted = false
    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "calSyncEnabled") {
        didSet { UserDefaults.standard.set(enabled, forKey: "calSyncEnabled") }
    }
    @Published var calendarID: String = UserDefaults.standard.string(forKey: "calendarID") ?? "" {
        didSet { UserDefaults.standard.set(calendarID, forKey: "calendarID") }
    }

    init() {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            accessGranted = true
            reload()
        }
    }

    @MainActor
    func requestAccess() async {
        let ok = (try? await store.requestFullAccessToEvents()) ?? false
        accessGranted = ok
        if ok { reload() }
    }

    func reload() {
        calendars = store.calendars(for: .event).filter { $0.allowsContentModifications }
        if calendarID.isEmpty || store.calendar(withIdentifier: calendarID) == nil {
            let google = calendars.first {
                $0.source.title.localizedCaseInsensitiveContains("gmail")
                || $0.source.title.localizedCaseInsensitiveContains("google")
            }
            calendarID = (google ?? store.defaultCalendarForNewEvents ?? calendars.first)?
                .calendarIdentifier ?? ""
        }
    }

    /// Crée ou met à jour l'événement ; le supprime si la tâche n'a plus de date.
    func sync(_ t: TodoItem) {
        guard enabled, accessGranted else { return }
        guard let due = t.dueDate else { remove(t); return }
        guard let cal = store.calendar(withIdentifier: calendarID) else { return }
        let existing = t.calendarEventID.flatMap { store.event(withIdentifier: $0) }
        let e = existing ?? EKEvent(eventStore: store)
        e.calendar = cal
        e.title = t.title
        e.notes = t.details
        e.startDate = due
        e.endDate = due.addingTimeInterval(1800)
        do {
            try store.save(e, span: .thisEvent)
            t.calendarEventID = e.eventIdentifier
        } catch {
            print("Agenda : \(error.localizedDescription)")
        }
    }

    func remove(_ t: TodoItem) {
        if accessGranted, let id = t.calendarEventID, let e = store.event(withIdentifier: id) {
            try? store.remove(e, span: .thisEvent)
        }
        t.calendarEventID = nil
    }
}

struct SettingsView: View {
    @ObservedObject private var cal = CalendarSync.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Écrire mes tâches dans l'agenda", isOn: $cal.enabled)
                } footer: {
                    Text("Seules les tâches avec une date et une heure sont ajoutées. Pour utiliser Google Agenda, ajoute ton compte Google dans Réglages → Calendrier → Comptes, puis choisis-le ci-dessous.")
                }
                if cal.enabled {
                    if cal.accessGranted {
                        Picker("Agenda", selection: $cal.calendarID) {
                            ForEach(cal.calendars, id: \.calendarIdentifier) { c in
                                Text("\(c.title) (\(c.source.title))").tag(c.calendarIdentifier)
                            }
                        }
                    } else {
                        Button("Autoriser l'accès à l'agenda") { Task { await cal.requestAccess() } }
                    }
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("OK") { dismiss() } }
            .onChange(of: cal.enabled) { _, on in
                if on && !cal.accessGranted { Task { await cal.requestAccess() } }
            }
            .task { if cal.enabled && !cal.accessGranted { await cal.requestAccess() } }
        }
    }
}
