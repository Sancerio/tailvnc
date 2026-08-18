import SwiftUI

struct RemoteDesktopView: View {
    @ObservedObject var session: RemoteSessionModel
    @State private var controlsExpanded = false
    @State private var keyboardActive = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let frame = session.frame, session.remoteSize != .zero {
                remoteImage(frame)
            } else {
                connectingView
            }

            chrome

            KeyboardCaptureView(
                isActive: keyboardActive,
                onText: session.sendText,
                onDelete: { session.sendKey(0xff08) },
                onReturn: { session.sendKey(0xff0d) }
            )
            .frame(width: 2, height: 2)
            .position(x: -4, y: -4)
            .accessibilityHidden(true)
        }
        .persistentSystemOverlays(.hidden)
        .onDisappear {
            keyboardActive = false
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

    private var chrome: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack {
                VStack {
                    HStack {
                        connectionIndicator
                        Spacer()
                    }
                    Spacer()
                }

                if isLandscape {
                    HStack {
                        Spacer()
                        controls(isLandscape: true)
                    }
                } else {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            controls(isLandscape: false)
                        }
                    }
                }
            }
            .padding(8)
        }
        .animation(.snappy(duration: 0.22), value: controlsExpanded)
        .animation(.snappy(duration: 0.22), value: keyboardActive)
    }

    private var connectionIndicator: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(session.frame == nil ? .orange : .green)
                .frame(width: 8, height: 8)

            if controlsExpanded || session.frame == nil {
                Text(session.statusText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .padding(controlsExpanded || session.frame == nil ? 10 : 8)
        .background(.ultraThinMaterial, in: Capsule())
        .allowsHitTesting(false)
    }

    private func controls(isLandscape: Bool) -> some View {
        let layout = isLandscape
            ? AnyLayout(VStackLayout(spacing: 4))
            : AnyLayout(HStackLayout(spacing: 4))

        return layout {
            if controlsExpanded {
                controlButton("Scroll up", systemImage: "arrow.up") {
                    session.scroll(up: true)
                }

                controlButton(
                    keyboardActive ? "Stop typing" : "Type on Mac",
                    systemImage: keyboardActive ? "keyboard.fill" : "keyboard"
                ) {
                    keyboardActive.toggle()
                }
                .foregroundStyle(keyboardActive ? .cyan : .primary)
                .accessibilityIdentifier("keyboardToggleButton")

                controlButton("Return", systemImage: "arrow.turn.down.left") {
                    session.sendKey(0xff0d)
                }

                controlButton("Scroll down", systemImage: "arrow.down") {
                    session.scroll(up: false)
                }

                controlButton("Disconnect", systemImage: "xmark") {
                    keyboardActive = false
                    session.disconnect()
                }
                .accessibilityIdentifier("disconnectButton")
            }

            Button {
                controlsExpanded.toggle()
            } label: {
                Image(systemName: controlsExpanded ? "chevron.right" : (keyboardActive ? "keyboard.fill" : "ellipsis"))
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(keyboardActive ? .cyan : .primary)
            .accessibilityLabel(controlsExpanded ? "Hide controls" : "Show controls")
            .accessibilityIdentifier("controlsToggleButton")
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    private func controlButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
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
