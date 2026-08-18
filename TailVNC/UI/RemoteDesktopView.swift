import SwiftUI

struct RemoteDesktopView: View {
    @ObservedObject var session: RemoteSessionModel
    @State private var showKeyboard = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let frame = session.frame, session.remoteSize != .zero {
                remoteImage(frame)
            } else {
                connectingView
            }

            VStack {
                statusBar
                Spacer()
                controls
            }
            .padding()
        }
        .sheet(isPresented: $showKeyboard) {
            RemoteKeyboardSheet(session: session)
                .presentationDetents([.height(230)])
                .presentationDragIndicator(.visible)
        }
    }

    private func remoteImage(_ image: CGImage) -> some View {
        GeometryReader { geometry in
            let displayRect = fittedRect(remoteSize: session.remoteSize, in: geometry.size)

            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .frame(width: displayRect.width, height: displayRect.height)
                .position(x: displayRect.midX, y: displayRect.midY)
                .gesture(pointerGesture(displayRect: displayRect))
        }
        .ignoresSafeArea()
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(.cyan)
            Text(session.statusText)
                .font(.headline)
            Text("The first raw framebuffer can take a moment on a large display.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(session.frame == nil ? .orange : .green)
                .frame(width: 8, height: 8)
            Text(session.statusText)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Button("Disconnect", systemImage: "xmark.circle.fill") {
                session.disconnect()
            }
            .labelStyle(.iconOnly)
            .font(.title3)
            .accessibilityIdentifier("disconnectButton")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var controls: some View {
        HStack(spacing: 12) {
            controlButton("Scroll up", systemImage: "arrow.up") {
                session.scroll(up: true)
            }
            controlButton("Keyboard", systemImage: "keyboard") {
                showKeyboard = true
            }
            controlButton("Scroll down", systemImage: "arrow.down") {
                session.scroll(up: false)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func controlButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 42, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func fittedRect(remoteSize: CGSize, in available: CGSize) -> CGRect {
        guard remoteSize.width > 0, remoteSize.height > 0 else { return .zero }
        let scale = min(available.width / remoteSize.width, available.height / remoteSize.height)
        let size = CGSize(width: remoteSize.width * scale, height: remoteSize.height * scale)
        return CGRect(
            x: (available.width - size.width) / 2,
            y: (available.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func pointerGesture(displayRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard let point = remotePoint(value.location, displayRect: displayRect) else { return }
                session.sendPointer(x: point.x, y: point.y, pressed: true)
            }
            .onEnded { value in
                guard let point = remotePoint(value.location, displayRect: displayRect) else { return }
                session.sendPointer(x: point.x, y: point.y, pressed: false)
            }
    }

    private func remotePoint(_ location: CGPoint, displayRect: CGRect) -> (x: UInt16, y: UInt16)? {
        guard displayRect.contains(location), session.remoteSize.width > 0, session.remoteSize.height > 0 else {
            return nil
        }
        let normalizedX = (location.x - displayRect.minX) / displayRect.width
        let normalizedY = (location.y - displayRect.minY) / displayRect.height
        let x = min(max(Int(normalizedX * session.remoteSize.width), 0), Int(session.remoteSize.width) - 1)
        let y = min(max(Int(normalizedY * session.remoteSize.height), 0), Int(session.remoteSize.height) - 1)
        return (UInt16(x), UInt16(y))
    }
}
