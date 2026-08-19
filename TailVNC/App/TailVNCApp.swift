import SwiftUI

@main
struct TailVNCApp: App {
    init() {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            UserDefaults.standard.removeObject(forKey: "lastHost")
            UserDefaults.standard.removeObject(forKey: "lastPort")
            UserDefaults.standard.removeObject(forKey: "rememberPassword")
            UserDefaults.standard.removeObject(forKey: "authenticationMode")
            UserDefaults.standard.removeObject(forKey: "lastMacUsername")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
