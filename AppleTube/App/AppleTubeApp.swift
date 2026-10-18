import SwiftUI

@main
struct AppleTubeApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color(red: 0.98, green: 0.18, blue: 0.28)) // Apple Music accent (#FA2D48)
        }
    }
}
