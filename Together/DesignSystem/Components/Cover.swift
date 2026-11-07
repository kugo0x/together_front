import SwiftUI

/// The design-system cover (`components/Cover/preview.html`): wordmark + tagline on `bg`, with the
/// space blocks and check circles on the right. A fixed 960×288 composition that scales to the
/// available width — usable as a wide onboarding / App Store banner.
struct Cover: View {
    var tagline = "Groceries, tasks and notes — together, or just for you."

    private static let size = CGSize(width: 960, height: 288)

    var body: some View {
        GeometryReader { geo in
            composition
                .frame(width: Self.size.width, height: Self.size.height)
                .scaleEffect(geo.size.width / Self.size.width, anchor: .topLeading)
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Together. \(tagline)")
    }

    private var composition: some View {
        ZStack(alignment: .topLeading) {
            TG.Colors.bg
            art.frame(width: 480, height: 288).clipped().offset(x: 480)
            VStack(alignment: .leading, spacing: 0) {
                Text("Together")
                    .font(TG.Font.rounded(88))
                    .foregroundStyle(TG.Colors.ink)
                    .tracking(-1.76)
                Text(tagline)
                    .font(TG.Font.subhead)
                    .foregroundStyle(TG.Colors.ink2)
                    .padding(.top, TG.Space.s3)
                    .padding(.leading, TG.Space.s1)
            }
            .dynamicTypeSize(.large)
            .frame(width: 440, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .padding(.leading, TG.Space.s8)
            .padding(.bottom, TG.Space.s8)
        }
    }

    /// Shapes in the 480×288 art box, coordinates from the SVG.
    private var art: some View {
        ZStack(alignment: .topLeading) {
            block(16, -16, 192, 280, 16, TG.Colors.shared)
            block(224, 96, 144, 168, 16, TG.Colors.personal)
            block(384, -16, 112, 208, 16, TG.Colors.sharedSoft)
            block(384, 208, 112, 56, 28, TG.Colors.personalSoft)
            disc(256, 56, 16, TG.Colors.alex)
            disc(280, 56, 16, TG.Colors.sam)

            ForEach(Array([48, 96, 144, 192, 240].enumerated()), id: \.offset) { index, y in
                ring(56, CGFloat(y), TG.Colors.onShared)
                if index >= 2 { tick(CGFloat(y)) }
            }
            ForEach(Array(zip([44, 92, 140, 188, 236], [96, 64, 80, 56, 88])), id: \.0) { y, w in
                block(88, CGFloat(y), CGFloat(w), 8, 4, TG.Colors.sharedSoft)
            }

            ring(256, 136, TG.Colors.onPersonal)
            ring(256, 184, TG.Colors.onPersonal)
            block(288, 132, 56, 8, 4, TG.Colors.personalSoft)
            block(288, 180, 40, 8, 4, TG.Colors.personalSoft)
        }
        .frame(width: 480, height: 288, alignment: .topLeading)
    }

    private func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: r, style: .continuous)
            .fill(color)
            .frame(width: w, height: h)
            .position(x: x + w / 2, y: y + h / 2)
    }

    private func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Color) -> some View {
        Circle().fill(color).frame(width: r * 2, height: r * 2).position(x: cx, y: cy)
    }

    private func ring(_ cx: CGFloat, _ cy: CGFloat, _ color: Color) -> some View {
        Circle().stroke(color, lineWidth: 2).frame(width: 26, height: 26).position(x: cx, y: cy)
    }

    /// `M50 {cy+0.5} l4.2 4.2 8-8.4`
    private func tick(_ cy: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: 50, y: cy + 0.5))
            p.addLine(to: CGPoint(x: 54.2, y: cy + 4.7))
            p.addLine(to: CGPoint(x: 62.2, y: cy - 3.7))
        }
        .stroke(TG.Colors.onShared, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
    }
}

// MARK: - Preview

struct CoverGallery: View {
    var body: some View {
        Cover().frame(width: 960)
    }
}

#Preview("Cover · Light") { CoverGallery().catalogCanvas() }
#Preview("Cover · Dark") { CoverGallery().catalogCanvas().preferredColorScheme(.dark) }
