import SwiftUI

@main
struct TogetherApp: App {
    var body: some Scene {
        WindowGroup {
            // Phase 1: the design-system catalog. Phase 2 replaces this with the tab shell.
            ComponentCatalogView()
        }
    }
}
