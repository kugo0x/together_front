import SwiftUI

/// The note editor: Private / Shared banner, title, plain-text body, checklist. Text autosaves (with the note's
/// version, merging a partner's edit if one lands in between); checklist lines save as you go. A Personal note can
/// move to Shared through the ConfirmSheet, with Undo; delete has Undo too.
struct NoteEditor: View {
    let noteID: Note.ID

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.space) private var space
    @Environment(\.selectSpace) private var selectSpace
    @Environment(\.dismiss) private var dismiss

    enum Field: Hashable {
        case title, body
        case item(ChecklistItem.ID)
    }

    @State private var title = ""
    @State private var text = ""
    /// What the store had when we last loaded or saved — the base for merging.
    @State private var base: (title: String, body: String, version: Int) = ("", "", 0)
    @State private var loaded = false
    @State private var confirmMove = false
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var focus: Field?

    /// Only ever the note in the active space — never shown in another one.
    private var note: Note? { store.note(noteID, in: space) }

    var body: some View {
        Group {
            if let note {
                editor(note)
            } else {
                // A move lands in the store a moment before the space switch reaches the environment; show nothing
                // for that instant instead of closing. Close only if the note is gone for good (deleted elsewhere).
                Color.clear.onAppear {
                    if !store.notes.contains(where: { $0.id == noteID }) { dismiss() }
                }
            }
        }
        // Switching to a space the note isn't in closes the editor; following the note there (Move, Undo) doesn't.
        .onChange(of: space) { _, new in
            if store.note(noteID, in: new) == nil { dismiss() }
        }
        .background(TG.Colors.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .confirmSheet(
            isPresented: $confirmMove,
            title: "Move to Shared?",
            message: "“\(note?.displayTitle ?? "Untitled")” will move to your Shared space. "
                + "\(store.partner?.name ?? "Your partner") will be able to see and edit it.",
            confirm: "Move to Shared",
            cancel: "Keep private",
            icon: .people
        ) { move() }
        .onAppear(perform: load)
        .onDisappear(perform: leave)
        .onChange(of: title) { scheduleSave() }
        .onChange(of: text) { scheduleSave() }
        .onChange(of: focus) { old, _ in dropEmptyItem(old) }
    }

    // MARK: Layout

    private func editor(_ note: Note) -> some View {
        List {
            banner(note)
                .listRowInsets(EdgeInsets(top: TG.Space.s1, leading: TG.Space.s4, bottom: TG.Space.s2, trailing: TG.Space.s4))
                .editorRow()

            VStack(alignment: .leading, spacing: TG.Space.s2) {
                TextField("Title", text: $title, prompt: Text("Title").foregroundStyle(TG.Colors.ink3), axis: .vertical)
                    .font(TG.Font.title2.weight(.bold))
                    .foregroundStyle(TG.Colors.ink)
                    .focused($focus, equals: .title)
                    .submitLabel(.next)
                    .onChange(of: title) { _, new in
                        // Return moves on to the body instead of breaking the title.
                        if new.contains("\n") {
                            title = new.replacingOccurrences(of: "\n", with: "")
                            focus = .body
                        }
                    }
                    .accessibilityLabel("Title")
                Text(meta(note))
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
            }
            .listRowInsets(EdgeInsets(top: TG.Space.s3, leading: TG.Space.s5, bottom: TG.Space.s2, trailing: TG.Space.s5))
            .editorRow()

            TextField("Note", text: $text, prompt: Text("Start writing…").foregroundStyle(TG.Colors.ink3), axis: .vertical)
                .lineLimit(5...)
                .font(TG.Font.body)
                .foregroundStyle(TG.Colors.ink)
                .focused($focus, equals: .body)
                .accessibilityLabel("Note")
                .listRowInsets(EdgeInsets(top: TG.Space.s2, leading: TG.Space.s5, bottom: TG.Space.s3, trailing: TG.Space.s5))
                .editorRow()

            Section {
                ForEach(note.checklist) { item in
                    checklistRow(item, in: note)
                }
                .onMove { from, to in
                    guard let source = from.first else { return }
                    let item = note.checklist[source]
                    store.updateChecklistItem(item.id, in: note.id, space: space, position: to > source ? to - 1 : to)
                }
                .onDelete { offsets in
                    for i in offsets { store.deleteChecklistItem(note.checklist[i].id, in: note.id, space: space) }
                }

                Button { addItem(after: nil, in: note) } label: {
                    Label { Text("Add checklist item") } icon: { Icon(.plus) }
                        .font(TG.Font.subhead.weight(.medium))
                        .foregroundStyle(Accent.of(note.space).ink)
                        .frame(minHeight: DS.minTarget)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 0, leading: TG.Space.s5, bottom: 0, trailing: TG.Space.s5))
                .editorRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func banner(_ note: Note) -> some View {
        let shared = note.space == .shared
        let accent = Accent.of(note.space)
        return HStack(spacing: TG.Space.s3) {
            Icon(shared ? .people : .lock)
                .foregroundStyle(accent.ink)
            Text(shared
                 ? "Shared with \(store.partner?.name ?? "your partner") — you can both edit this note."
                 : "Private — only you can see this note.")
                .font(TG.Font.footnote)
                .foregroundStyle(TG.Colors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, TG.Space.s3)
        .padding(.horizontal, TG.Space.s4)
        .background(accent.soft, in: RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func checklistRow(_ item: ChecklistItem, in note: Note) -> some View {
        HStack(spacing: TG.Space.s3) {
            CheckCircle(checked: item.done, label: (item.done ? "Untick " : "Tick ") + (item.label.isEmpty ? "item" : item.label)) {
                store.updateChecklistItem(item.id, in: note.id, space: space, done: !item.done)
            }
            .environment(\.space, note.space)
            TextField("Checklist item", text: Binding(
                get: { item.label },
                set: { store.updateChecklistItem(item.id, in: note.id, space: space, text: $0) }
            ), prompt: Text("Item").foregroundStyle(TG.Colors.ink3))
                .font(TG.Font.body)
                .foregroundStyle(item.done ? TG.Colors.ink2 : TG.Colors.ink)
                .strikethrough(item.done, color: TG.Colors.ink3)
                .focused($focus, equals: .item(item.id))
                .submitLabel(.next)
                .accessibilityLabel("Checklist item")
                .onSubmit { addItem(after: item, in: note) }
        }
        .frame(minHeight: DS.minTarget)
        .listRowInsets(EdgeInsets(top: 0, leading: TG.Space.s4, bottom: 0, trailing: TG.Space.s5))
        .editorRow()
        .accessibilityAction(named: "Move up") { move(item, by: -1, in: note) }
        .accessibilityAction(named: "Move down") { move(item, by: 1, in: note) }
        .accessibilityAction(named: "Delete") { store.deleteChecklistItem(item.id, in: note.id, space: space) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let note {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if note.space == .personal, store.partner != nil {
                    // Words, not the share glyph: that icon alone reads as the system Share sheet.
                    Button("Move to Shared") { confirmMove = true }
                        .fontWeight(.semibold)
                        .tint(Accent.of(.shared).ink)
                }
                Button(role: .destructive) { delete() } label: {
                    Label("Delete note", systemImage: IconName.trash.systemName)
                }
                .tint(TG.Colors.danger)
            }
            // Above the keyboard, so adding a line or finishing never needs the keyboard out of the way.
            ToolbarItemGroup(placement: .keyboard) {
                Button { addItem(after: focusedItem(in: note), in: note) } label: {
                    Label { Text("Add checklist item") } icon: { Icon(.plus) }
                        .labelStyle(.titleAndIcon)
                }
                .tint(Accent.of(note.space).ink)
                Spacer()
                Button("Done") { focus = nil }
                    .fontWeight(.semibold)
                    .tint(Accent.of(note.space).ink)
            }
        }
    }

    private func focusedItem(in note: Note) -> ChecklistItem? {
        guard case .item(let id)? = focus else { return nil }
        return note.checklist.first { $0.id == id }
    }

    private func meta(_ note: Note) -> String {
        let edited = "edited " + store.dates.past(note.updatedAt, midSentence: true)
        guard note.space == .shared else { return "Private · " + edited }
        let by = note.updatedBy == store.me ? "you" : note.updatedBy.name
        return "Shared · \(edited) by \(by)"
    }

    // MARK: Text: load, autosave, merge

    private func load() {
        guard !loaded, let note else { return }
        loaded = true
        title = note.title
        text = note.body
        base = (note.title, note.body, note.version)
        if note.isEmpty { focus = .title }
    }

    private func scheduleSave() {
        guard loaded else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    /// Saves title/body if they changed. On a version conflict (the partner saved in between), keeps whichever
    /// side changed each field — mine wins only where I edited — and retries once.
    private func save(retry: Bool = true) {
        guard loaded, title != base.title || text != base.body else { return }
        switch store.updateNote(noteID, in: space, title: title, body: text, ifMatch: base.version) {
        case .success(let saved)?:
            base = (saved.title, saved.body, saved.version)
        case .failure(let conflict)?:
            let current = conflict.current
            let mergedTitle = title == base.title ? current.title : title
            let mergedBody = text == base.body ? current.body : text
            base = (current.title, current.body, current.version)
            title = mergedTitle
            text = mergedBody
            if retry { save(retry: false) }
        case nil:
            break
        }
    }

    private func leave() {
        saveTask?.cancel()
        save()
        // A new note left empty isn't kept.
        if let note, note.isEmpty { store.deleteNote(note.id, in: space) }
    }

    // MARK: Checklist

    private func addItem(after item: ChecklistItem?, in note: Note) {
        let position = item.flatMap { current in note.checklist.firstIndex { $0.id == current.id } }.map { $0 + 1 }
        if let new = store.addChecklistItem("", to: note.id, in: space, at: position) {
            focus = .item(new.id)
        }
    }

    /// An item left empty when focus moves away is removed.
    private func dropEmptyItem(_ field: Field?) {
        guard case .item(let id)? = field, let note,
              let item = note.checklist.first(where: { $0.id == id }),
              item.label.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        store.deleteChecklistItem(id, in: note.id, space: space)
    }

    private func move(_ item: ChecklistItem, by offset: Int, in note: Note) {
        guard let i = note.checklist.firstIndex(where: { $0.id == item.id }) else { return }
        store.updateChecklistItem(item.id, in: note.id, space: space, position: i + offset)
    }

    // MARK: Move and delete

    private func move() {
        save()
        guard store.moveNote(noteID, from: .personal, to: .shared) != nil else { return }
        selectSpace(.shared)
        toasts.showUndo("Moved to Shared") {
            if store.moveNote(noteID, from: .shared, to: .personal) != nil {
                selectSpace(.personal)
            }
        }
    }

    private func delete() {
        saveTask?.cancel()
        save()
        let space = space
        guard let deleted = store.deleteNote(noteID, in: space) else { return }
        dismiss()
        guard !deleted.note.isEmpty else { return }
        toasts.showUndo("Note deleted") { store.restoreNote(noteID, in: space) }
    }
}

private extension View {
    /// Editor rows sit straight on the page: no row background, no separators.
    func editorRow() -> some View {
        listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
}
