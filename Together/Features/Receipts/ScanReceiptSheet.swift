import AVFoundation
import PhotosUI
import SwiftUI
import VisionKit

/// Scan receipt (design: ScanReceipt → reading → ReceiptReview). Photos go to the backend to be read and matched
/// (`ReceiptRecognizer`); the review is applied only on Confirm. One receipt can be 1–5 photos; several receipts
/// are read in parallel and reviewed one by one (`ReceiptScanFlow`).
struct ScanReceiptSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.space) private var space
    @Environment(\.receiptRecognizer) private var recognizer
    @Environment(\.receiptTestInput) private var testInput
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flow: ReceiptScanFlow?
    @State private var showCamera = false
    @State private var cameraDenied = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var choosingPhotos = false
    @State private var editing: ReceiptReview.Line?
    @State private var preparing = false

    var body: some View {
        Group {
            if let flow {
                content(flow)
            }
        }
        .background(TG.Colors.surface)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(flow?.step == .receipts || flow?.step == .pages)
        .fullScreenCover(isPresented: $showCamera) {
            DocumentCamera { pages in
                showCamera = false
                if !pages.isEmpty { prepare { try pages.map { try ReceiptImage.jpeg(from: $0) } } }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $choosingPhotos, selection: $photos, maxSelectionCount: photoLimit,
                      selectionBehavior: .ordered, matching: .images)
        .onChange(of: photos) { loadPhotos() }
        .sheet(item: $editing) { line in
            LineEditSheet(line: line) { name, price in
                flow?.editReview {
                    $0.rename(line.id, to: name)
                    $0.setPrice(line.id, price)
                }
            }
        }
        .onAppear(perform: start)
        .onDisappear { flow?.cancelAll() }
    }

    private func start() {
        guard flow == nil else { return }
        let flow = ReceiptScanFlow(recognizer: recognizer, store: store, space: space)
        self.flow = flow
        // UI tests: no camera or Photos — blank pages go through the same pipeline.
        switch testInput {
        case .photos(let count, let separate)?:
            prepare(asPhotos: true, separate: separate) { try (0..<count).map { _ in try ReceiptImage.jpeg(from: Self.blankPage()) } }
        case nil:
            break
        }
    }

    @ViewBuilder
    private func content(_ flow: ReceiptScanFlow) -> some View {
        switch flow.step {
        case .capture: fullPage { capture(flow) }
        case .pages: pagesView(flow)
        case .chooseGrouping: fullPage { grouping(flow) }
        case .receipts: receiptView(flow)
        case .finished: fullPage { finished(flow) }
        }
    }

    /// Fills the sheet (spacers keep their layout) but scrolls when large text needs more room.
    private func fullPage<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let content = content()
        return GeometryReader { geometry in
            ScrollView {
                content.frame(minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// While adding to a receipt: up to 5 photos in all. From scratch: several receipts may be picked at once.
    private var photoLimit: Int {
        flow?.step == .pages ? max(1, ReceiptScanFlow.maxPages - (flow?.pages.count ?? 0)) : 10
    }

    // MARK: Capture

    private func capture(_ flow: ReceiptScanFlow) -> some View {
        VStack(spacing: TG.Space.s5) {
            header("Scan receipt")
            VStack(spacing: TG.Space.s3) {
                Icon(.receipt)
                    .font(TG.Font.largeTitle)
                    .foregroundStyle(TG.Colors.ink3)
                Text("Fit the whole receipt in the frame. A long one can take a few photos.")
                    .font(TG.Font.subhead)
                    .foregroundStyle(TG.Colors.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TG.Space.s4)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(TG.Colors.surface2, in: RoundedRectangle(cornerRadius: TG.Radius.xl, style: .continuous))
            .accessibilityElement(children: .combine)

            cameraDeniedNote
            sourceButtons(adding: false)
            TGButton("Cancel", variant: .plain, block: true) { dismiss() }
            Spacer(minLength: 0)
            privacyNote
        }
        .padding(TG.Space.s5)
        .overlay { if preparing { ProgressView().controlSize(.large) } }
    }

    @ViewBuilder
    private var cameraDeniedNote: some View {
        if cameraDenied {
            VStack(spacing: TG.Space.s2) {
                Text("Allow camera access in Settings to scan receipts. You can also pick photos.")
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
                    .multilineTextAlignment(.center)
                TGButton("Open Settings", variant: .plain, size: .sm) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
        }
    }

    private func sourceButtons(adding: Bool) -> some View {
        VStack(spacing: TG.Space.s3) {
            TGButton(adding ? "Take another photo" : "Scan with camera", icon: .camera, variant: adding ? .secondary : .primary,
                     block: true, action: openCamera)
                .disabled(!VNDocumentCameraViewController.isSupported)
            TGButton(adding ? "Add from Photos" : "Choose from Photos", icon: .image, variant: .secondary, block: true) {
                photos = []
                choosingPhotos = true
            }
            if !VNDocumentCameraViewController.isSupported, !adding {
                Text("The camera isn’t available here — choose photos of the receipt instead.")
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var privacyNote: some View {
        Label {
            Text("The photo is sent to read the receipt and isn’t kept.")
        } icon: {
            Icon(.lock)
        }
        .font(TG.Font.footnote)
        .foregroundStyle(TG.Colors.ink2)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func openCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            showCamera = true
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted { showCamera = true } else { cameraDenied = true }
            }
        default:
            cameraDenied = true
        }
    }

    private func loadPhotos() {
        let items = photos
        guard !items.isEmpty else { return }
        photos = []
        prepare(asPhotos: true) {
            // Loaded below on the main actor; the closure only converts.
            []
        } loader: {
            var out: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) { out.append(data) }
            }
            return out
        }
    }

    /// JPEG, ≤ 1568 px, no metadata — off the main thread. Camera pages are pages of one receipt; photos from
    /// Photos go through the grouping question when there are several.
    private func prepare(asPhotos: Bool = false, separate: Bool? = nil,
                         _ make: @escaping @Sendable () throws -> [Data],
                         loader: (@MainActor () async -> [Data])? = nil) {
        preparing = true
        Task {
            defer { preparing = false }
            var jpegs: [Data] = []
            if let loader {
                let raw = await loader()
                jpegs = (try? await Task.detached(priority: .userInitiated) {
                    raw.compactMap { try? ReceiptImage.jpeg(from: $0) }
                }.value) ?? []
            } else {
                jpegs = (try? await Task.detached(priority: .userInitiated, operation: make).value) ?? []
            }
            guard let flow, !jpegs.isEmpty else { return }
            if asPhotos {
                flow.photosPicked(jpegs)
                switch separate {
                case true?: flow.groupAsSeparateReceipts()
                case false? where flow.step == .chooseGrouping: flow.groupAsOneReceipt()
                default: break
                }
            } else {
                flow.addPages(jpegs)
            }
        }
    }

    nonisolated private static func blankPage() -> CGImage {
        let context = CGContext(data: nil, width: 600, height: 1200, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 1200))
        return context.makeImage()!
    }

    // MARK: Pages of one receipt

    private func pagesView(_ flow: ReceiptScanFlow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TG.Space.s5) {
                header("Scan receipt", subtitle: flow.pages.count == 1
                       ? "1 photo of this receipt"
                       : "\(flow.pages.count) photos of this receipt, top to bottom")
                VStack(spacing: 0) {
                    ForEach(Array(flow.pages.enumerated()), id: \.element.id) { index, page in
                        if index > 0 { RowSeparator() }
                        pageRow(page, index: index, count: flow.pages.count, flow: flow)
                    }
                }
                .background(TG.Colors.bg, in: RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))

                if flow.canAddPage {
                    VStack(alignment: .leading, spacing: TG.Space.s2) {
                        Text("Add another photo of this receipt")
                            .font(TG.Font.subhead.weight(.semibold))
                            .foregroundStyle(TG.Colors.ink)
                        sourceButtons(adding: true)
                    }
                } else {
                    Text("That’s the most for one receipt (5 photos).")
                        .font(TG.Font.footnote)
                        .foregroundStyle(TG.Colors.ink2)
                }
                cameraDeniedNote
                privacyNote
            }
            .padding(TG.Space.s5)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: TG.Space.s2) {
                TGButton("Read receipt", icon: .receipt, block: true) { flow.readPages() }
                TGButton("Cancel", variant: .plain, block: true) { dismiss() }
            }
            .padding(.horizontal, TG.Space.s5)
            .padding(.vertical, TG.Space.s3)
            .background(TG.Colors.surface)
        }
        .overlay { if preparing { ProgressView().controlSize(.large) } }
    }

    private func pageRow(_ page: ReceiptScanFlow.Page, index: Int, count: Int, flow: ReceiptScanFlow) -> some View {
        HStack(spacing: TG.Space.s3) {
            Group {
                if let image = UIImage(data: page.jpeg) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    TG.Colors.surface2
                }
            }
            .frame(width: 44, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: TG.Radius.sm, style: .continuous))
            .accessibilityHidden(true)
            Text("Photo \(index + 1)")
                .font(TG.Font.body)
                .foregroundStyle(TG.Colors.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { flow.movePage(from: index, to: index - 1) } label: { Icon(.chevron).rotationEffect(.degrees(-90)) }
                .buttonStyle(.bare).hitArea(24).disabled(index == 0)
                .accessibilityLabel("Move photo \(index + 1) up")
            Button { flow.movePage(from: index, to: index + 1) } label: { Icon(.chevron).rotationEffect(.degrees(90)) }
                .buttonStyle(.bare).hitArea(24).disabled(index == count - 1)
                .accessibilityLabel("Move photo \(index + 1) down")
            Button { flow.removePage(page.id) } label: { Icon(.trash) }
                .buttonStyle(.bare).hitArea(24)
                .foregroundStyle(TG.Colors.danger)
                .accessibilityLabel("Remove photo \(index + 1)")
        }
        .font(TG.Font.body)
        .foregroundStyle(TG.Colors.ink2)
        .padding(.horizontal, TG.Space.s4)
        .padding(.vertical, TG.Space.s2)
    }

    // MARK: Grouping

    /// Never guessed: the person says whether the photos are one receipt or several.
    private func grouping(_ flow: ReceiptScanFlow) -> some View {
        VStack(alignment: .leading, spacing: TG.Space.s4) {
            header("\(flow.pendingPhotos.count) photos", subtitle: "How do they go together?")
            groupingOption(icon: .receipt, title: "These are parts of one receipt",
                           detail: flow.pendingPhotos.count > ReceiptScanFlow.maxPages
                               ? "A long receipt in up to 5 photos — the first 5 are used"
                               : "A long receipt in several photos → one trip") { flow.groupAsOneReceipt() }
            groupingOption(icon: .history, title: "Separate receipts",
                           detail: "Each photo is its own receipt → a trip each") { flow.groupAsSeparateReceipts() }
            TGButton("Cancel", variant: .plain, block: true) { flow.startOver() }
            Spacer(minLength: 0)
        }
        .padding(TG.Space.s5)
    }

    private func groupingOption(icon: IconName, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: TG.Space.s4) {
                Icon(icon).font(TG.Font.title3).foregroundStyle(Accent.of(space).ink)
                    .frame(width: 44, height: 44).background(Accent.of(space).soft, in: Circle())
                VStack(alignment: .leading, spacing: DS.rowLineGap) {
                    Text(title).font(TG.Font.headline).foregroundStyle(TG.Colors.ink)
                    Text(detail).font(TG.Font.subhead).foregroundStyle(TG.Colors.ink2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chevron).font(TG.Font.footnote.weight(.semibold)).foregroundStyle(TG.Colors.ink3)
            }
            .padding(TG.Space.s4)
            .background(TG.Colors.bg, in: RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.bare)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Receipts (reading → review, one at a time)

    @ViewBuilder
    private func receiptView(_ flow: ReceiptScanFlow) -> some View {
        switch flow.currentReceipt?.state {
        case .reading?: reading(flow)
        case .failed(let error)?: fullPage { failed(error, flow: flow) }
        case .ready(let review)?: reviewView(review, flow: flow)
        default: EmptyView()
        }
    }

    /// Skeleton rows, no spinner (design-system README "Receipts and money").
    private func reading(_ flow: ReceiptScanFlow) -> some View {
        VStack(alignment: .leading, spacing: TG.Space.s5) {
            if let progress = flow.progress { progressLabel(progress) }
            HStack(spacing: TG.Space.s3) {
                Icon(.receipt)
                    .font(TG.Font.title3)
                    .foregroundStyle(Accent.of(space).ink)
                    .frame(width: 44, height: 44)
                    .background(Accent.of(space).soft, in: Circle())
                VStack(alignment: .leading, spacing: DS.rowLineGap) {
                    Text("Reading the receipt…").font(TG.Font.headline).foregroundStyle(TG.Colors.ink)
                    Text("Matching items with your list").font(TG.Font.subhead).foregroundStyle(TG.Colors.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            TGGroup {
                ForEach([0.55, 0.4, 0.65, 0.35, 0.5], id: \.self) { width in
                    HStack(spacing: TG.Space.s3) {
                        Circle().fill(TG.Colors.surface2).frame(width: DS.checkSize, height: DS.checkSize)
                        GeometryReader { g in
                            RoundedRectangle(cornerRadius: TG.Radius.sm).fill(TG.Colors.surface2)
                                .frame(width: g.size.width * width, height: 12)
                                .frame(maxHeight: .infinity)
                        }
                        RoundedRectangle(cornerRadius: TG.Radius.sm).fill(TG.Colors.surface2).frame(width: 48, height: 12)
                    }
                    .frame(height: DS.rowMinHeight)
                    .padding(.horizontal, TG.Space.s4)
                }
            }
            .padding(.horizontal, -TG.Space.s4)
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            TGButton("Cancel", variant: .secondary, block: true) { flow.cancelReading() }
        }
        .padding(TG.Space.s5)
    }

    private func failed(_ error: ReceiptScanError, flow: ReceiptScanFlow) -> some View {
        VStack(spacing: TG.Space.s4) {
            if let progress = flow.progress { progressLabel(progress) }
            Spacer()
            EmptyState(title: error.title, message: error.message, icon: error == .offline ? .close : .receipt)
            if error.canRetry {
                TGButton("Try again", block: true) { flow.retryCurrent() }
            }
            if flow.isQueue {
                TGButton("Skip this receipt", variant: .secondary, block: true) { flow.skipCurrent() }
            } else {
                TGButton(error.canRetry ? "Use another photo" : "Try another photo",
                         variant: error.canRetry ? .secondary : .primary, block: true) { flow.startOver() }
            }
            TGButton("Cancel", variant: .plain, block: true) { dismiss() }
            Spacer()
        }
        .padding(TG.Space.s5)
    }

    private func progressLabel(_ text: String) -> some View {
        Text(text)
            .font(TG.Font.caption)
            .tracking(DS.captionTracking)
            .textCase(.uppercase)
            .foregroundStyle(TG.Colors.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reviewView(_ review: ReceiptReview, flow: ReceiptScanFlow) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TG.Space.s5) {
                if let progress = flow.progress { progressLabel(progress) }
                header("Review receipt", subtitle: subtitle(review))

                if !review.matched.isEmpty {
                    section("On your list", count: review.matched.count, lines: review.matched)
                }
                if !review.extra.isEmpty {
                    VStack(alignment: .leading, spacing: TG.Space.s2) {
                        section("Not on your list", count: review.extra.count, lines: review.extra)
                        Text("These go to your history and help suggestions — they won’t be added to the list.")
                            .font(TG.Font.footnote)
                            .foregroundStyle(TG.Colors.ink2)
                    }
                }
                if !review.unclear.isEmpty {
                    section("Couldn’t read", count: review.unclear.count, lines: review.unclear)
                }

                totalRow(review)
                Text(space == .shared
                     ? "Saved to Shared history — \(store.partner?.name ?? "your partner") can see this receipt."
                     : "Saved to your Personal history — only you can see it.")
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
            }
            .padding(TG.Space.s5)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: TG.Space.s2) {
                TGButton(review.confirmTitle, icon: .check, block: true) { flow.confirmCurrent() }
                TGButton(flow.isQueue ? "Skip this receipt" : "Discard", variant: .secondary, block: true) {
                    if flow.isQueue { flow.skipCurrent() } else { dismiss() }
                }
            }
            .padding(.horizontal, TG.Space.s5)
            .padding(.vertical, TG.Space.s3)
            .background(TG.Colors.surface)
        }
    }

    /// The review on screen (for the row helpers below).
    private var review: ReceiptReview? {
        if case .ready(let review)? = flow?.currentReceipt?.state { return review }
        return nil
    }

    // MARK: Finished

    private func finished(_ flow: ReceiptScanFlow) -> some View {
        VStack(spacing: TG.Space.s4) {
            Spacer()
            Icon(.check)
                .font(TG.Font.title2)
                .foregroundStyle(Accent.of(space).on)
                .frame(width: 56, height: 56)
                .background(Accent.of(space).fill, in: Circle())
                .accessibilityHidden(true)
            Text(flow.summary)
                .font(TG.Font.title3)
                .foregroundStyle(TG.Colors.ink)
                .multilineTextAlignment(.center)
            Text("It’s in History.")
                .font(TG.Font.subhead)
                .foregroundStyle(TG.Colors.ink2)
            Spacer()
            TGButton("Scan another receipt", icon: .camera, variant: .secondary, block: true) { flow.scanAnother() }
            TGButton("Done", block: true) { dismiss() }
        }
        .padding(TG.Space.s5)
    }

    // MARK: Review pieces

    private func section(_ title: String, count: Int, lines: [ReceiptReview.Line]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: title, count: count)
                .padding(.horizontal, -TG.Space.s4)
            VStack(spacing: 0) {
                ForEach(lines) { line in
                    if line.id != lines.first?.id { RowSeparator() }
                    lineRow(line)
                }
            }
            .background(TG.Colors.bg, in: RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))
        }
    }

    private func lineRow(_ line: ReceiptReview.Line) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ReceiptLineRow(
                name: line.status == .matched ? (line.match?.name ?? line.name) : line.name,
                qty: line.qty,
                price: line.price.map(Money.pln) ?? "—",
                status: line.status,
                included: line.included,
                onToggle: { flow?.editReview { $0.toggle(line.id) } },
                onFix: { editing = line }
            )
            .contentShape(Rectangle())
            .onTapGesture { editing = line }
            .accessibilityAction(named: "Edit") { editing = line }
            .contextMenu {
                if line.status != .matched { chooseItems(for: line) }
                if line.status != .extra { Button("Not on the list") { flow?.editReview { $0.keepAsExtra(line.id) } } }
                Button("Edit name or price") { editing = line }
            }

            if line.status == .unclear {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TG.Space.s2) {
                        if let candidate = line.didYouMean {
                            Text("Did you mean").font(TG.Font.footnote).foregroundStyle(TG.Colors.ink2)
                            Chip(candidate.name) { flow?.editReview { $0.acceptSuggestion(line.id) } }
                        }
                        if !(review?.freeCandidates(for: line.id).isEmpty ?? true) {
                            Menu { chooseItems(for: line) } label: {
                                Chip("Choose from your list", icon: .chevronDown) {}
                                    .allowsHitTesting(false)
                            }
                            .accessibilityLabel("Choose from your list")
                        }
                        Chip("Not on the list") { flow?.editReview { $0.keepAsExtra(line.id) } }
                    }
                    .padding(.horizontal, TG.Space.s4)
                    .padding(.bottom, TG.Space.s3)
                }
            }
        }
    }

    /// The list items a line can be pointed at by hand (nothing is matched for the person).
    @ViewBuilder
    private func chooseItems(for line: ReceiptReview.Line) -> some View {
        ForEach(review?.freeCandidates(for: line.id) ?? [], id: \.itemID) { candidate in
            Button(candidate.name) { flow?.editReview { $0.assign(line.id, to: candidate) } }
        }
    }

    private func totalRow(_ review: ReceiptReview) -> some View {
        VStack(alignment: .leading, spacing: TG.Space.s1) {
            HStack {
                Text("Receipt total").font(TG.Font.headline).foregroundStyle(TG.Colors.ink)
                Spacer()
                TextField("Total", text: Binding(
                    get: { review.total.map { Money.number($0) } ?? "" },
                    set: { text in flow?.editReview { $0.total = Money.parse(text) } }
                ), prompt: Text("0,00"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(TG.Font.headline.monospacedDigit())
                    .frame(maxWidth: 120)
                    .accessibilityLabel("Receipt total")
                Text("zł").font(TG.Font.headline).foregroundStyle(TG.Colors.ink)
            }
            if let total = review.total, abs(NSDecimalNumber(decimal: total - review.includedSum).doubleValue) >= 0.01 {
                Text("The ticked lines add up to \(Money.pln(review.includedSum)).")
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
            }
        }
        .padding(TG.Space.s4)
        .background(TG.Colors.bg, in: RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))
    }

    /// Title with the space badge beside it; with large text the badge goes above so neither wraps mid-word.
    private func header(_ title: String, subtitle: String? = nil) -> some View {
        let heading = Text(title).font(TG.Font.title3).foregroundStyle(TG.Colors.ink).accessibilityAddTraits(.isHeader)
        return VStack(alignment: .leading, spacing: DS.rowLineGap) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    heading.fixedSize()
                    Spacer()
                    PrivacyBadge(space: space).fixedSize()
                }
                VStack(alignment: .leading, spacing: TG.Space.s2) {
                    PrivacyBadge(space: space).fixedSize()
                    heading
                }
            }
            if let subtitle { Text(subtitle).font(TG.Font.subhead).foregroundStyle(TG.Colors.ink2) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Biedronka · today, 18:42"
    private func subtitle(_ review: ReceiptReview) -> String {
        let dates = store.dates
        let day = dates.past(review.date, midSentence: true)
        let time = TimeOfDay(review.date, calendar: store.calendar).text
        let when = (day == "just now" || day.hasSuffix("ago") ? "today" : day) + ", " + time
        return [review.merchant, when].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Fix a line: what it really says, and its price.
private struct LineEditSheet: View {
    let line: ReceiptReview.Line
    let onSave: (String, Decimal?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var price: String

    init(line: ReceiptReview.Line, onSave: @escaping (String, Decimal?) -> Void) {
        self.line = line
        self.onSave = onSave
        _name = State(initialValue: line.status == .unclear && !line.name.contains(where: \.isLetter) ? "" : line.name)
        _price = State(initialValue: line.price.map(Money.number) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Item", text: $name, prompt: Text("What is it?"))
                        .accessibilityLabel("Item name")
                    TextField("Price", text: $price, prompt: Text("0,00"))
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Price")
                } footer: {
                    Text("Read as “\(line.name)”")
                }
            }
            .navigationTitle("Fix line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, Money.parse(price))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// VisionKit's document camera: finds the receipt's edges and flattens it. Returns the scanned pages.
private struct DocumentCamera: UIViewControllerRepresentable {
    let onFinish: ([CGImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([CGImage]) -> Void

        init(onFinish: @escaping ([CGImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            onFinish([])
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            onFinish([])
        }
    }
}
