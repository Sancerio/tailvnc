import SwiftUI

struct ContentView: View {
    @StateObject private var session = RemoteSessionModel()

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
