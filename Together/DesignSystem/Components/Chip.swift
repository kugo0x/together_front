import SwiftUI

/// A selectable pill for one choice in a sheet (who / when / repeat / reminder). Selected takes the space fill.
/// Use 2–5 short options in one row; never two rows deep.
struct Chip: View {
    let title: String
    var icon: IconName?
    var selected = false
    let action: () -> Void

    init(_ title: String, icon: IconName? = nil, selected: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.selected = selected
        self.action = action
    }

    @Environment(\.accent) private var accent
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 36

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Icon(icon).imageScale(.small) }
                Text(title).lineLimit(1)
            }
            .font(TG.Font.subhead.weight(.medium))
            .foregroundStyle(selected ? accent.on : TG.Colors.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: height)
            .background(selected ? accent.fill : TG.Colors.surface2, in: Capsule())
            .hitArea(height)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Preview

struct ChipGallery: View {
    @State private var selection = "Morning of · 9:00"
    private let options = ["Morning of · 9:00", "Day before · 19:00", "Pick time", "Off"]

    var body: some View {
        FlowLayout(spacing: TG.Space.s2, lineSpacing: TG.Space.s2) {
            ForEach(options, id: \.self) { option in
                Chip(option, icon: option == "Off" ? nil : .bell, selected: selection == option) {
                    selection = option
                }
            }
        }
        .padding(TG.Space.s4)
        .frame(width: 520, alignment: .leading)
    }
}

#Preview("Chip · Light") { ChipGallery().catalogCanvas() }
#Preview("Chip · Dark") { ChipGallery().catalogCanvas().preferredColorScheme(.dark) }
#Preview("Chip · Personal") { ChipGallery().catalogCanvas().environment(\.space, .personal) }
