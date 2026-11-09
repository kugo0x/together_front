import SwiftUI

@main
struct TogetherApp: App {
    var body: some Scene {
        WindowGroup {
            // Launch with `-catalog YES` to browse the design-system components instead of the shell.
            if UserDefaults.standard.bool(forKey: "catalog") {
                ComponentCatalogView()
            } else {
                AppRoot()
            }
        }
    }
}
