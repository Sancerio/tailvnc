import SwiftUI

struct ContentView: View {
    @StateObject private var session: RemoteSessionModel

    init() {
        let session = RemoteSessionModel()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-remote") {
            session.prepareUITestSession()
        }
#endif
        _session = StateObject(wrappedValue: session)
    }

    var body: some View {
        Group {
            if session.isSessionVisible {
                RemoteDesktopView(session: session)
            } else {
                ConnectionView(session: session)
            }
        }
        .preferredColorScheme(.dark)
    }
}
