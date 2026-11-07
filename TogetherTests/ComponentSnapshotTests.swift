import SwiftUI
import UIKit
import XCTest
@testable import Together

/// Renders every catalog gallery in light and dark to PNG (@2x, the reference screenshots' scale)
/// for side-by-side comparison with `design/screenshots/components`.
///
/// Opt-in: runs only when `SNAPSHOT_DIR` is set, e.g.
/// `TEST_RUNNER_SNAPSHOT_DIR=$PWD/build/snapshots xcodebuild test ... -only-testing:TogetherTests/ComponentSnapshotTests`
@MainActor
final class ComponentSnapshotTests: XCTestCase {
    func testRenderCatalog() throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_SNAPSHOT_DIR to render component snapshots")
        }
        let output = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        for entry in ComponentCatalog.entries {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let image = render(entry, style: style, scene: scene)
                let name = "\(entry.name)-\(style == .dark ? "dark" : "light").png"
                try XCTUnwrap(image.pngData()).write(to: output.appendingPathComponent(name))
            }
        }
    }

    private func render(_ entry: CatalogEntry, style: UIUserInterfaceStyle, scene: UIWindowScene) -> UIImage {
        let size = entry.canvas
        let root = entry.view()
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(TG.Colors.bg)
            .environment(\.dynamicTypeSize, .large)
        let host = UIHostingController(rootView: root)
        host.safeAreaRegions = []
        host.overrideUserInterfaceStyle = style

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        window.isHidden = true
        return image
    }
}
