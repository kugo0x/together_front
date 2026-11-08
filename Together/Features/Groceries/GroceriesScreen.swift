import SwiftUI

/// Groceries (HANDOFF §6.3): suggestions card, To buy, Bought (collapsed), Recent trips, and the
/// QuickAdd bar pinned above the tab bar. Everything is the active space's default list.
///
/// Behaviour follows the prototype (design/prototype/Main.dc.html, `groceryVM` / `acceptSugg` / `skipSugg`):
/// checking → Bought + "X bought · Undo"; swipe to delete → "X removed · Undo"; tap a row to edit it.
struct GroceriesScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.space) private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showBought = false
    @State private var editing: GroceryItem?

    var body: some View {
        // Re-render every minute so "2 min ago" stays true.
        TimelineView(.everyMinute) { _ in
            list(dates: store.dates)
        }
        .toastHost()
        .safeAreaInset(edge: .bottom, spacing: 0) { quickAddBar }
        .sheet(item: $editing) { item in
            GroceryEditSheet(item: item) { name, qty, note in
                store.updateItem(item.id, in: space, name: name, qty: qty, note: note)
            }
        }
    }

    // MARK: Sections

    private func list(dates: RelativeDate) -> some View {
        let toBuy = store.toBuy(in: space)
        let bought = store.bought(in: space)
        let suggestions = store.suggestions(in: space)
        let trips = store.recentTrips(in: space)

        return ShellList(subtitle: subtitle(toBuy: toBuy.count)) {
            if !suggestions.isEmpty {
                Section {
                    SuggestionCard(
                        items: suggestions,
                        title: "Before \(shoppingDayName)’s shop",
                        onAdd: { add([$0]) },
                        onSkip: skip,
                        onAddAll: suggestions.count > 1 ? { add(suggestions) } : nil
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }

            ShellSection(title: "To buy", count: toBuy.count) {
                if toBuy.isEmpty {
                    EmptyState(title: "Nothing to buy", message: "Add something below, or check this week’s suggestions.")
                } else {
                    ForEach(toBuy) { item in row(item, dates: dates) }
                }
            }

            if !bought.isEmpty {
                ShellSection(title: "Bought", count: bought.count, action: showBought ? "Hide" : "Show") {
                    withAnimation(.tg(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)) { showBought.toggle() }
                } content: {
                    if showBought {
                        ForEach(bought) { item in row(item, dates: dates) }
                    }
                }
            }

            if !trips.isEmpty {
                // "History" (the header action in the design) arrives with receipts in phase 8.
                ShellSection(title: "Recent trips") {
                    ForEach(trips) { trip in TripRow(trip: trip, me: store.me) }
                }
            }
        }
    }

    private func row(_ item: GroceryItem, dates: RelativeDate) -> some View {
        GroceryItemRow(item: item, dates: dates, me: store.me) { toggle(item) }
            .contentShape(Rectangle())
            .onTapGesture { editing = item }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { remove(item) } label: {
                    Label("Delete", systemImage: IconName.trash.systemName)
                }
                .tint(TG.Colors.danger)
            }
            .accessibilityAction(named: "Edit") { editing = item }
            .accessibilityAction(named: "Delete") { remove(item) }
    }

    private var quickAddBar: some View {
        QuickAdd(placeholder: space == .shared ? "Add to Shared groceries" : "Add to my list") { name, qty in
            withAnimation(.tg(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
                _ = store.addItem(name: name, qty: qty, in: space)
            }
        }
        .padding(.horizontal, TG.Space.s4)
        .padding(.top, TG.Space.s2)
        .padding(.bottom, TG.Space.s2)
        .background(TG.Colors.bg)
        .overlay(alignment: .top) { TG.Colors.separator.frame(height: DS.hairline) }
    }

    // MARK: Copy

    private func subtitle(toBuy: Int) -> String {
        let who = space == .shared
            ? store.partner.map { "Shared with \($0.name)" } ?? "Shared space"
            : "Only you can see this list"
        return "\(toBuy) to buy · \(who)"
    }

    private var shoppingDayName: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        return calendar.weekdaySymbols[(store.shoppingDay - 1 + 7) % 7]
    }

    // MARK: Actions

    private func toggle(_ item: GroceryItem) {
        let space = space
        withAnimation(.tg(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)) {
            if item.done {
                _ = store.unmarkBought(item.id, in: space)
            } else {
                _ = store.markBought(item.id, in: space)
            }
        }
        if !item.done {
            toasts.showUndo("\(item.name) bought") { store.unmarkBought(item.id, in: space) }
        }
    }

    private func remove(_ item: GroceryItem) {
        guard let removed = store.removeItem(item.id, in: space) else { return }
        toasts.showUndo("\(item.name) removed") { store.undoRemove(removed) }
    }

    private func add(_ suggestions: [Suggestion]) {
        let added = withAnimation(.tg(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
            store.acceptSuggestions(named: suggestions.map(\.name), in: space)
        }
        if suggestions.count == 1, let first = suggestions.first {
            toasts.show("\(first.name) added to the list")
        } else {
            toasts.show(added.count == 1 ? "1 item added" : "\(added.count) items added")
        }
    }

    private func skip(_ suggestion: Suggestion) {
        withAnimation(.tg(.easeOut(duration: 0.2), reduceMotion: reduceMotion)) {
            store.dismissSuggestion(named: suggestion.name, in: space)
        }
        toasts.show("Skipped \(suggestion.name) this week")
    }
}

/// A row in Recent trips: receipt (or cart) icon, date, who · items, total.
struct TripRow: View {
    let trip: Trip
    var me: Person = .alex

    var body: some View {
        HStack(spacing: TG.Space.s3) {
            Icon(trip.hasReceipt ? .receipt : .cart)
                .font(TG.Font.body)
                .foregroundStyle(TG.Colors.ink2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.rowLineGap) {
                Text(trip.dateText())
                    .font(TG.Font.body)
                    .foregroundStyle(TG.Colors.ink)
                Text(trip.metaText(me: me))
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            Text(trip.amountText)
                .font(TG.Font.body)
                .monospacedDigit()
                .foregroundStyle(trip.total == nil ? TG.Colors.ink3 : TG.Colors.ink)
                .accessibilityLabel(trip.total == nil ? "No total" : trip.amountText)
        }
        .padding(.vertical, TG.Space.s3)
        .padding(.horizontal, TG.Space.s4)
        .frame(minHeight: DS.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}
