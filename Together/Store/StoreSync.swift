import Foundation

/// Receives every change the store makes locally, to send it to the server (`RemoteSync`). Each change carries
/// what is needed to send it and to undo it if the server refuses.
@MainActor
protocol StoreSync: AnyObject {
    func record(_ change: StoreChange)
    /// A trip's receipt lines, fetched when it is opened in History.
    func loadLines(of tripID: Trip.ID) async
    /// Membership changed outside the store (an invite created the Shared space, a code joined one): re-learn the
    /// spaces and load them.
    func spacesChanged() async
}

/// A local change, in the store's words. The API call for each lives in `RemoteSync`.
enum StoreChange {
    // Groceries
    case itemAdded(GroceryItem, SpaceKind)
    case itemEdited(GroceryItem, SpaceKind)
    case itemBought(GroceryItem.ID, SpaceKind)
    case itemUnbought(GroceryItem.ID, SpaceKind)
    case itemRemoved(GroceryItem, SpaceKind)
    /// Undo of a removal: the API re-adds it (and ticks it again if it was bought).
    case itemRestored(GroceryItem, SpaceKind)
    case suggestionDismissed(String, SpaceKind)
    case suggestionsAccepted([String], added: [GroceryItem], SpaceKind)
    case receiptConfirmed(ReceiptReview, trip: Trip, SpaceKind)

    // Tasks
    case taskCreated(TaskItem, AppStore.TaskDraft)
    case taskEdited(TaskItem, AppStore.TaskDraft, before: TaskItem)
    /// The task as it was before completing (for rollback).
    case taskCompleted(TaskItem)
    case taskReopened(TaskItem)
    case taskDeleted(TaskItem)
    /// Undo of a delete — there's no restore endpoint, so it is created again.
    case taskRestored(TaskItem)

    // Notes
    case noteCreated(Note)
    /// `base` is the note the edit started from (its version goes in `If-Match`).
    case noteEdited(Note, base: Note)
    case noteDeleted(Note)
    case noteRestored(Note)
    case noteMoved(Note, from: SpaceKind)
    case checklistAdded(ChecklistItem, note: Note.ID, at: Int, SpaceKind)
    case checklistEdited(ChecklistItem.ID, note: Note.ID, text: String?, done: Bool?, position: Int?, SpaceKind)
    case checklistDeleted(ChecklistItem.ID, note: Note.ID, SpaceKind)

    // Me, settings, membership
    case settingsChanged
    case shoppingDayChanged(Int)
    case quietHoursChanged(QuietHours)
    case avatarChanged(Data?)
    case leftShared
}

/// What the offline banner shows.
enum ConnectionState: Equatable, Sendable {
    case online
    /// Changes are waiting to be sent.
    case offline(pending: Int)
}
