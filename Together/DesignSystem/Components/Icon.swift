import SwiftUI

/// Icon names from the design-system bundle, mapped to SF Symbols (README › Iconography, HANDOFF §3).
/// Size and weight follow the surrounding text style (set `.font` on the icon or its parent), so icons scale
/// with Dynamic Type. Colour is `ink-2` or the space accent — set by the parent.
enum IconName: String, CaseIterable, Sendable {
    case plus, check, cart, tasks, note, home, lock, people, person
    case `repeat`, calendar, chevron, chevronDown, search, more, close, history
    case arrowUp, share, trash, gear, bell, camera, receipt, image

    var systemName: String {
        switch self {
        case .plus: "plus"
        case .check: "checkmark"
        case .cart: "cart"
        case .tasks: "checklist"
        case .note: "note.text"
        case .home: "house"
        case .lock: "lock"
        case .people: "person.2"
        case .person: "person"
        case .repeat: "arrow.triangle.2.circlepath"
        case .calendar: "calendar"
        case .chevron: "chevron.right"
        case .chevronDown: "chevron.down"
        case .search: "magnifyingglass"
        case .more: "ellipsis"
        case .close: "xmark"
        case .history: "clock.arrow.circlepath"
        case .arrowUp: "arrow.up"
        case .share: "square.and.arrow.up"
        case .trash: "trash"
        case .gear: "gearshape"
        case .bell: "bell"
        case .camera: "camera"
        case .receipt: "receipt"
        case .image: "photo"
        }
    }
}

/// An SF Symbol for a design-system icon name. Decorative by default (hidden from VoiceOver);
/// pass `label` only when the icon is the sole content of a control.
struct Icon: View {
    let name: IconName
    var label: String?

    init(_ name: IconName, label: String? = nil) {
        self.name = name
        self.label = label
    }

    var body: some View {
        if let label {
            Image(systemName: name.systemName)
                .accessibilityLabel(label)
        } else {
            Image(systemName: name.systemName)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Preview

struct IconGallery: View {
    private let names: [IconName] = [
        .home, .cart, .tasks, .note, .plus, .check, .people, .lock, .person, .repeat, .calendar, .history,
        .search, .share, .trash, .gear, .more, .chevron, .close, .arrowUp,
    ]

    var body: some View {
        FlowLayout(spacing: 18, lineSpacing: 18) {
            ForEach(names, id: \.self) { name in
                Icon(name, label: name.rawValue)
                    .font(TG.Font.title2.weight(.regular))
                    .frame(width: 24, height: 24)
            }
        }
        .foregroundStyle(TG.Colors.ink2)
        .padding(TG.Space.s4)
    }
}

#Preview("Icon · Light") { IconGallery().catalogCanvas() }
#Preview("Icon · Dark") { IconGallery().catalogCanvas().preferredColorScheme(.dark) }
