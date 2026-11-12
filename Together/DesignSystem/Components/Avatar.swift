import SwiftUI

/// A round initial for Alex or Sam; `person == nil` draws the dashed "invite partner" ghost.
/// Fill is the person's token, initials `on-person` in the rounded family.
/// A person with a profile photo (`avatarPhotos` in the environment) shows it instead of the initial.
struct Avatar: View {
    let person: Person?
    var size: CGFloat = 32
    @Environment(\.avatarPhotos) private var photos

    var body: some View {
        if let person, let photo = photos[person.id] {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(person.name)
        } else if let person {
            Text(person.initial)
                .font(TG.Font.rounded((size * 0.42).rounded()))
                .foregroundStyle(TG.Colors.onPerson)
                .frame(width: size, height: size)
                .background(person.color, in: Circle())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(person.name)
        } else {
            Image(systemName: IconName.plus.systemName)
                .resizable()
                .scaledToFit()
                .fontWeight(.light)
                .frame(width: size * 0.36, height: size * 0.36)
                .foregroundStyle(TG.Colors.ink2)
                .frame(width: size, height: size)
                .background(TG.Colors.surface2, in: Circle())
                .overlay(Circle().strokeBorder(TG.Colors.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5])))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Invite partner")
        }
    }
}

/// Alex and Sam overlapping (`.tg-pair`); `partner == nil` shows the invite ghost.
struct AvatarPair: View {
    var me: Person = .alex
    var partner: Person? = .sam
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: -TG.Space.s2) {
            Avatar(person: me, size: size)
            Avatar(person: partner, size: size)
                .background(Circle().fill(TG.Colors.surface).padding(-2))
        }
    }
}

// MARK: - Preview

struct AvatarGallery: View {
    var body: some View {
        HStack(spacing: TG.Space.s3) {
            Avatar(person: .alex, size: 40)
            Avatar(person: .sam, size: 40)
            Avatar(person: nil, size: 40)
            Avatar(person: .sam, size: 26)
            AvatarPair(size: 32)
        }
        .padding(TG.Space.s4)
    }
}

#Preview("Avatar · Light") { AvatarGallery().catalogCanvas() }
#Preview("Avatar · Dark") { AvatarGallery().catalogCanvas().preferredColorScheme(.dark) }

private struct AvatarPhotosKey: EnvironmentKey {
    static let defaultValue: [Person.ID: UIImage] = [:]
}

extension EnvironmentValues {
    /// Profile photos by person (`AppStore.avatarPhotos`), set once at the root.
    var avatarPhotos: [Person.ID: UIImage] {
        get { self[AvatarPhotosKey.self] }
        set { self[AvatarPhotosKey.self] = newValue }
    }
}
