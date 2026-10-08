import SwiftUI

@main struct DecimaApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                // The app is designed dark; this keeps glass and system controls matching
                .preferredColorScheme(.dark)
        }
    }
}
