import SwiftUI
import SwiftData

struct SheetState: Identifiable {
    let id = UUID()
    var item: TodoItem?
    var prefill = ParsedTask(title: "", details: "", due: nil)
}

struct ContentView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var items: [TodoItem]
    @StateObject private var rec = SpeechRecorder()
    @State private var sheet: SheetState?
    @State private var showSettings = false

    private var sorted: [TodoItem] {
        items.sorted {
            if $0.isDone != $1.isDone { return !$0.isDone }
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("Aucune tâche. Appuie sur le micro et dicte-en une.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sorted) { t in
                    row(t)
                }
                .onDelete { idx in
                    for i in idx {
                        let t = sorted[i]
                        Reminders.cancel(t)
                        CalendarSync.shared.remove(t)
                        ctx.delete(t)
                    }
                }
            }
            .navigationTitle("Vocal To-Do")
            .toolbar {
                ToolbarItemGroup {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    Button { sheet = SheetState() } label: { Image(systemName: "plus") }
                }
            }
            .safeAreaInset(edge: .bottom) { micBar }
        }
        .sheet(item: $sheet) { EditorView(state: $0) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task {
            await Reminders.requestPermission()
            rec.onFinished = { text in
                sheet = SheetState(item: nil, prefill: VoiceParser.parse(text))
            }
        }
    }

    private func row(_ t: TodoItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                t.isDone.toggle()
                Reminders.schedule(t) // annule le rappel si terminé
            } label: {
                Image(systemName: t.isDone ? "checkmark.circle.fill" : "circle").font(.title2)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).strikethrough(t.isDone).foregroundStyle(t.isDone ? .secondary : .primary)
                if !t.details.isEmpty {
                    Text(t.details).font(.subheadline).foregroundStyle(.secondary)
                }
                if let d = t.dueDate {
                    Label(d.formatted(date: .abbreviated, time: .shortened), systemImage: "bell")
                        .font(.caption)
                        .foregroundStyle(!t.isDone && d < Date() ? .red : .secondary)
                }
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { sheet = SheetState(item: t) }
    }

    private var micBar: some View {
        VStack(spacing: 6) {
            if rec.isRecording || !rec.transcript.isEmpty {
                Text(rec.transcript.isEmpty ? "Je t'écoute…" : "« \(rec.transcript) »")
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            }
            if let e = rec.errorMessage {
                Text(e).font(.footnote).foregroundStyle(.red)
            }
            Button { rec.toggle() } label: {
                Image(systemName: rec.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30)).foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(rec.isRecording ? Color.red : Color.accentColor, in: Circle())
            }
            Text(rec.isRecording ? "Appuie pour terminer" : "Titre, date/heure, puis « description : … »")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

struct EditorView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let state: SheetState

    @State private var title = ""
    @State private var details = ""
    @State private var hasDue = false
    @State private var due = Date().addingTimeInterval(3600)

    var body: some View {
        NavigationStack {
            Form {
                Section("Tâche") { TextField("Titre", text: $title) }
                Section("Rappel") {
                    Toggle("Planifier un rappel", isOn: $hasDue)
                    if hasDue { DatePicker("Date et heure", selection: $due) }
                }
                Section("Détails") {
                    TextField("Description", text: $details, axis: .vertical).lineLimit(3...8)
                }
            }
            .navigationTitle(state.item == nil ? "Nouvelle tâche" : "Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        if let t = state.item {
            title = t.title; details = t.details
            if let d = t.dueDate { hasDue = true; due = d }
        } else {
            title = state.prefill.title; details = state.prefill.details
            if let d = state.prefill.due { hasDue = true; due = d }
        }
    }

    private func save() {
        let t = state.item ?? TodoItem(title: title)
        t.title = title.trimmingCharacters(in: .whitespaces)
        t.details = details
        t.dueDate = hasDue ? due : nil
        if state.item == nil { ctx.insert(t) }
        Reminders.schedule(t)
        CalendarSync.shared.sync(t)
        dismiss()
    }
}
