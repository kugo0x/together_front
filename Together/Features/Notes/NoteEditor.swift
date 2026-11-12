import SwiftUI

/// The note editor: Private / Shared banner, then one plain-text field — the first line is the title (like Notes),
/// the rest the body. It autosaves with the note's version, merging a partner's edit if one lands in between. A
/// Personal note can move to Shared through the ConfirmSheet, with Undo; delete has Undo too. No checklist, no
/// formatting (decided 2026-11-12): a list is just lines of text.
struct NoteEditor: View {
    let noteID: Note.ID

    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.space) private var space
    @Environment(\.selectSpace) private var selectSpace
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    /// What the store had when we last loaded or saved — the base for merging.
    @State private var base: (title: String, body: String, version: Int) = ("", "", 0)
    @State private var loaded = false
    @State private var confirmMove = false
    @State private var saveTask: Task<Void, Never>?
    /// The server merged my save with the partner's (version conflict): say so until dismissed.
    @State private var showMerged = false
    @FocusState private var focused: Bool

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
        .onChange(of: text) { scheduleSave() }
        .onChange(of: store.noteMerges[noteID]) { _, merges in if merges != nil { adoptMerge() } }
    }

    // MARK: Layout

    private func editor(_ note: Note) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TG.Space.s3) {
                banner(note)
                if showMerged { mergedNotice }
                Text(meta(note))
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
                    .padding(.horizontal, TG.Space.s1)
                TextField("Note", text: $text,
                          prompt: Text("Start writing — the first line is the title").foregroundStyle(TG.Colors.ink3),
                          axis: .vertical)
                    .lineLimit(12...)
                    .font(TG.Font.body)
                    .foregroundStyle(TG.Colors.ink)
                    .focused($focused)
                    .accessibilityLabel("Note")
                    .padding(.horizontal, TG.Space.s1)
            }
            .padding(.horizontal, TG.Space.s4)
            .padding(.vertical, TG.Space.s2)
        }
        .scrollDismissesKeyboard(.interactively)
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

    /// After a conflict: both edits are in the note now.
    private var mergedNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: TG.Space.s3) {
            Text("\(store.partner?.name ?? "Your partner") edited this note at the same time. Both changes are kept — "
                 + "yours where you typed, theirs elsewhere.")
                .font(TG.Font.footnote)
                .foregroundStyle(TG.Colors.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("OK") { showMerged = false }
                .font(TG.Font.footnote.weight(.semibold))
                .foregroundStyle(TG.Colors.ink)
                .hitArea(44)
        }
        .padding(.vertical, TG.Space.s2)
        .padding(.horizontal, TG.Space.s4)
        .background(TG.Colors.surface2, in: RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Dismiss") { showMerged = false }
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
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
                    .fontWeight(.semibold)
                    .tint(Accent.of(note.space).ink)
            }
        }
    }

    private func meta(_ note: Note) -> String {
        let edited = "edited " + store.dates.past(note.updatedAt, midSentence: true)
        guard note.space == .shared else { return "Private · " + edited }
        let by = note.updatedBy == store.me ? "you" : note.updatedBy.name
        return "Shared · \(edited) by \(by)"
    }

    // MARK: Text: load, autosave, merge

    /// The server merged a save of mine with the partner's: take theirs for a field (first line / rest) I haven't
    /// touched since that save, keep what I'm typing otherwise (it saves on top of the merged version).
    private func adoptMerge() {
        guard let note else { return }
        let mine = Note.split(text)
        text = Note.join(title: mine.title == base.title ? note.title : mine.title,
                         body: mine.body == base.body ? note.body : mine.body)
        base = (note.title, note.body, note.version)
        showMerged = true
    }

    private func load() {
        guard !loaded, let note else { return }
        loaded = true
        text = note.text
        base = (note.title, note.body, note.version)
        if note.isEmpty { focused = true }
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

    /// Saves if the text changed. On a version conflict (the partner saved in between), keeps whichever side
    /// changed each part — mine wins only where I edited — and retries once.
    private func save(retry: Bool = true) {
        let (title, body) = Note.split(text)
        guard loaded, title != base.title || body != base.body else { return }
        switch store.updateNote(noteID, in: space, title: title, body: body, ifMatch: base.version) {
        case .success(let saved)?:
            base = (saved.title, saved.body, saved.version)
        case .failure(let conflict)?:
            let current = conflict.current
            let mergedTitle = title == base.title ? current.title : title
            let mergedBody = body == base.body ? current.body : body
            base = (current.title, current.body, current.version)
            text = Note.join(title: mergedTitle, body: mergedBody)
            showMerged = true // the partner's save arrived (event stream) while I was typing
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
