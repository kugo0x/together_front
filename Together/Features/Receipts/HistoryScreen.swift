import SwiftUI

/// History (design: History): one month line and the trips by month. Money appears only here and as trip totals —
/// no charts, categories or budgets (design-system README "Receipts and money").
struct HistoryScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.space) private var space

    var body: some View {
        let months = store.tripMonths(in: space)
        let current = store.monthSummary(containing: store.now, in: space)
        let previousDate = store.calendar.date(byAdding: .month, value: -1, to: store.now) ?? store.now
        let previous = store.monthSummary(containing: previousDate, in: space)

        List {
            Text(space == .shared
                 ? store.partner.map { "Shared with \($0.name)" } ?? "Shared space"
                 : "Personal · only you can see this")
                .font(TG.Font.subhead)
                .foregroundStyle(TG.Colors.ink2)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 0, leading: TG.Space.s4, bottom: TG.Space.s2, trailing: TG.Space.s4))

            Section {
                monthLine(current, previous: previous)
            }
            .tgListRow()

            if months.isEmpty {
                EmptyState(title: "No trips yet", message: "Scan a receipt after shopping to see it here.", icon: .receipt)
                    .listRowBackground(Color.clear)
            }
            ForEach(months) { month in
                ShellSection(title: month.name) {
                    ForEach(month.trips) { trip in
                        NavigationLink {
                            TripDetail(trip: trip)
                        } label: {
                            TripRow(trip: trip, me: store.me)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { store.deleteTrip(trip.id) } label: {
                                Label("Delete", systemImage: IconName.trash.systemName)
                            }
                            .tint(TG.Colors.danger)
                        }
                        .accessibilityAction(named: "Delete") { store.deleteTrip(trip.id) }
                    }
                }
            }

            Text("Totals come from scanned receipts. Items from every trip help Together suggest what you might have forgotten.")
                .font(TG.Font.footnote)
                .foregroundStyle(TG.Colors.ink2)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(TG.Space.s6)
        .scrollContentBackground(.hidden)
        .background(TG.Colors.bg)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.large)
    }

    /// "Groceries in November · 352,60 zł" with "3 trips with receipts · October 412,02 zł".
    private func monthLine(_ month: TripMonth, previous: TripMonth) -> some View {
        VStack(alignment: .leading, spacing: TG.Space.s1) {
            Text("Groceries in \(month.name)")
                .font(TG.Font.subhead)
                .foregroundStyle(TG.Colors.ink2)
            Text(Money.pln(month.total))
                .font(TG.Font.title2.monospacedDigit())
                .foregroundStyle(TG.Colors.ink)
            Text(meta(month, previous: previous))
                .font(TG.Font.footnote)
                .foregroundStyle(TG.Colors.ink2)
        }
        .padding(TG.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func meta(_ month: TripMonth, previous: TripMonth) -> String {
        let n = month.tripsWithTotal
        let trips = n == 1 ? "1 trip with a receipt" : "\(n) trips with receipts"
        guard !previous.trips.isEmpty else { return trips }
        return "\(trips) · \(previous.name) \(Money.pln(previous.total))"
    }
}

/// One trip: where, when, the total, and the lines from its receipt.
struct TripDetail: View {
    /// The row that was tapped; the live version (with its lines, once loaded) comes from the store.
    let tapped: Trip
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The receipt lines are fetched when the trip is opened (`GET /trips/{id}`); until then the empty state waits.
    @State private var linesLoaded = false

    init(trip: Trip) { tapped = trip }

    private var trip: Trip { store.trips.first { $0.id == tapped.id } ?? tapped }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: TG.Space.s1) {
                    Text(trip.dateText()).font(TG.Font.headline).foregroundStyle(TG.Colors.ink)
                    Text(trip.metaText(me: store.me)).font(TG.Font.footnote).foregroundStyle(TG.Colors.ink2)
                    Text(trip.amountText).font(TG.Font.title3.monospacedDigit()).foregroundStyle(TG.Colors.ink)
                        .padding(.top, TG.Space.s1)
                }
                .padding(TG.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
            .tgListRow()

            if trip.lines.isEmpty, !linesLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if trip.lines.isEmpty {
                Text(trip.hasReceipt ? "This receipt’s lines weren’t kept." : "No receipt for this trip.")
                    .font(TG.Font.subhead)
                    .foregroundStyle(TG.Colors.ink2)
                    .listRowBackground(Color.clear)
            } else {
                ShellSection(title: "On the receipt", count: trip.lines.count) {
                    ForEach(trip.lines) { line in
                        ReceiptLineRow(
                            name: line.name,
                            qty: line.qty,
                            price: line.price.map(Money.pln) ?? "—",
                            status: line.status == .matched ? .matched : line.status == .unclear ? .unclear : .extra
                        )
                        .allowsHitTesting(false)
                    }
                }
            }

            Section {
                TGButton("Delete trip", icon: .trash, variant: .destructive, block: true) {
                    store.deleteTrip(tapped.id)
                    dismiss()
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(TG.Colors.bg)
        .task {
            await store.loadLines(of: tapped.id)
            linesLoaded = true
        }
        .navigationTitle(trip.merchant ?? "Trip")
        .navigationBarTitleDisplayMode(.inline)
    }
}
