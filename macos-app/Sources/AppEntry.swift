import SwiftUI

@main
struct AutoBrowsingApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AutoBrowsingAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.automatic)
    }
}
