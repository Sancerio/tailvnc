import SwiftUI

struct RemoteDesktopView: View {
    @ObservedObject var session: RemoteSessionModel
    @State private var controlsExpanded = false
    @State private var keyboardActive = false
    @State private var zoomScale: CGFloat = 1
    @State private var zoomOffset: CGSize = .zero
    @State private var magnifyStartScale: CGFloat?
    @State private var magnifyStartOffset: CGSize = .zero
    @State private var panStartOffset: CGSize?
    @State private var isMagnifying = false
    @State private var lastRemotePointer: (x: UInt16, y: UInt16)?
    @State private var inputFeedbackVisible = false

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
            resetZoom()
        }
        .onChange(of: session.inputActivitySequence) { _, sequence in
            withAnimation(.easeOut(duration: 0.12)) {
                inputFeedbackVisible = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                guard session.inputActivitySequence == sequence else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    inputFeedbackVisible = false
                }
            }
        }
    }

    private func remoteImage(_ image: CGImage) -> some View {
        GeometryReader { geometry in
            let displayRect = RemoteViewport.fittedRect(remoteSize: session.remoteSize, in: geometry.size)
            let transformedRect = RemoteViewport.transformedRect(
                displayRect,
                scale: zoomScale,
                offset: zoomOffset
            )

            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(session.performanceMode == .responsive ? .low : .high)
                    .frame(width: transformedRect.width, height: transformedRect.height)
                    .position(x: transformedRect.midX, y: transformedRect.midY)

                Color.clear
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Remote desktop")
                    .accessibilityIdentifier("remoteViewport")
                    .gesture(
                        interactionGesture(
                            displayRect: displayRect,
                            transformedRect: transformedRect,
                            available: geometry.size
                        )
                    )
                    .simultaneousGesture(
                        magnifyGesture(displayRect: displayRect, available: geometry.size)
                    )
            }
            .clipped()
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
            Text("Optimizing the first frame for \(session.performanceMode.title.lowercased()) mode…")
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
                .fill(inputFeedbackVisible ? .cyan : (session.frame == nil ? .orange : .green))
                .frame(width: 8, height: 8)

            if inputFeedbackVisible {
                Image(systemName: "paperplane.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.cyan)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Input sent")
                    .accessibilityIdentifier("inputFeedbackIndicator")
            }

            if controlsExpanded || session.frame == nil {
                Text(session.statusText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }

            if zoomScale > 1.01 {
                Text(Double(zoomScale).formatted(.number.precision(.fractionLength(1))) + "×")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.cyan)
                    .accessibilityIdentifier("zoomIndicator")
            }

            if controlsExpanded, session.frame != nil {
                Image(systemName: session.performanceMode.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
                    .accessibilityLabel(session.performanceMode.title + " stream quality")
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

                qualityMenu

                if zoomScale > 1.01 {
                    controlButton("Reset zoom", systemImage: "arrow.counterclockwise") {
                        withAnimation(.snappy(duration: 0.22)) {
                            resetZoom()
                        }
                    }
                    .accessibilityIdentifier("resetZoomButton")
                }

                controlButton("Disconnect", systemImage: "xmark") {
                    keyboardActive = false
                    resetZoom()
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

    private var qualityMenu: some View {
        Menu {
            ForEach(RFBPerformanceMode.allCases) { mode in
                Button {
                    session.setPerformanceMode(mode)
                } label: {
                    Label {
                        Text(mode.title + (mode == session.performanceMode ? " — Selected" : ""))
                        Text(mode.detail)
                    } icon: {
                        Image(systemName: mode.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: session.performanceMode.systemImage)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Stream quality, \(session.performanceMode.title)")
        .accessibilityIdentifier("qualityMenu")
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

    private func interactionGesture(
        displayRect: CGRect,
        transformedRect: CGRect,
        available: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !isMagnifying else { return }

                if zoomScale > 1.01 {
                    let start = panStartOffset ?? zoomOffset
                    if panStartOffset == nil {
                        panStartOffset = start
                    }
                    let proposed = CGSize(
                        width: start.width + value.translation.width,
                        height: start.height + value.translation.height
                    )
                    zoomOffset = RemoteViewport.clampedOffset(
                        proposed,
                        displayRect: displayRect,
                        scale: zoomScale,
                        available: available
                    )
                    return
                }

                guard let point = RemoteViewport.remotePoint(
                    value.location,
                    transformedRect: transformedRect,
                    remoteSize: session.remoteSize
                ) else { return }
                lastRemotePointer = point
                session.sendPointer(x: point.x, y: point.y, pressed: true)
            }
            .onEnded { value in
                defer { panStartOffset = nil }
                guard !isMagnifying else { return }

                if zoomScale > 1.01 {
                    let distance = hypot(value.translation.width, value.translation.height)
                    guard distance < 8,
                          let point = RemoteViewport.remotePoint(
                              value.location,
                              transformedRect: RemoteViewport.transformedRect(
                                  displayRect,
                                  scale: zoomScale,
                                  offset: zoomOffset
                              ),
                              remoteSize: session.remoteSize
                          ) else { return }
                    session.sendPointer(x: point.x, y: point.y, pressed: true)
                    session.sendPointer(x: point.x, y: point.y, pressed: false)
                    refreshAfterClick()
                    return
                }

                guard let point = RemoteViewport.remotePoint(
                    value.location,
                    transformedRect: transformedRect,
                    remoteSize: session.remoteSize
                ) else { return }
                lastRemotePointer = nil
                session.sendPointer(x: point.x, y: point.y, pressed: false)
                let distance = hypot(value.translation.width, value.translation.height)
                if distance < 8 {
                    refreshAfterClick()
                }
            }
    }

    private func refreshAfterClick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            session.refreshScreen()
        }
    }

    private func magnifyGesture(displayRect: CGRect, available: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if magnifyStartScale == nil {
                    magnifyStartScale = zoomScale
                    magnifyStartOffset = zoomOffset
                    isMagnifying = true
                    if let point = lastRemotePointer {
                        session.sendPointer(x: point.x, y: point.y, pressed: false)
                        lastRemotePointer = nil
                    }
                }

                let startScale = magnifyStartScale ?? zoomScale
                let targetScale = min(
                    max(startScale * value.magnification, RemoteViewport.minimumScale),
                    RemoteViewport.maximumScale
                )
                let anchor = CGPoint(
                    x: available.width * value.startAnchor.x,
                    y: available.height * value.startAnchor.y
                )
                let anchoredOffset = RemoteViewport.offsetKeepingAnchor(
                    anchor,
                    available: available,
                    startScale: startScale,
                    targetScale: targetScale,
                    startOffset: magnifyStartOffset
                )

                zoomScale = targetScale
                zoomOffset = RemoteViewport.clampedOffset(
                    anchoredOffset,
                    displayRect: displayRect,
                    scale: targetScale,
                    available: available
                )
            }
            .onEnded { _ in
                if zoomScale < 1.02 {
                    resetZoom()
                }
                magnifyStartScale = nil
                isMagnifying = false
                panStartOffset = nil
            }
    }

    private func resetZoom() {
        zoomScale = RemoteViewport.minimumScale
        zoomOffset = .zero
        magnifyStartScale = nil
        panStartOffset = nil
        isMagnifying = false
        lastRemotePointer = nil
    }
}

struct RemoteViewport {
    static let minimumScale: CGFloat = 1
    static let maximumScale: CGFloat = 4
    static let edgeRevealPadding: CGFloat = 56

    static func fittedRect(remoteSize: CGSize, in available: CGSize) -> CGRect {
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

    static func transformedRect(_ displayRect: CGRect, scale: CGFloat, offset: CGSize) -> CGRect {
        let size = CGSize(width: displayRect.width * scale, height: displayRect.height * scale)
        return CGRect(
            x: displayRect.midX + offset.width - size.width / 2,
            y: displayRect.midY + offset.height - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    static func clampedOffset(
        _ proposed: CGSize,
        displayRect: CGRect,
        scale: CGFloat,
        available: CGSize
    ) -> CGSize {
        let scaledWidth = displayRect.width * scale
        let scaledHeight = displayRect.height * scale
        let maximumX = scaledWidth > available.width
            ? (scaledWidth - available.width) / 2 + edgeRevealPadding
            : 0
        let maximumY = scaledHeight > available.height
            ? (scaledHeight - available.height) / 2 + edgeRevealPadding
            : 0
        return CGSize(
            width: min(max(proposed.width, -maximumX), maximumX),
            height: min(max(proposed.height, -maximumY), maximumY)
        )
    }

    static func offsetKeepingAnchor(
        _ anchor: CGPoint,
        available: CGSize,
        startScale: CGFloat,
        targetScale: CGFloat,
        startOffset: CGSize
    ) -> CGSize {
        guard startScale > 0 else { return startOffset }
        let ratio = targetScale / startScale
        let center = CGPoint(x: available.width / 2, y: available.height / 2)
        return CGSize(
            width: anchor.x - center.x - (anchor.x - center.x - startOffset.width) * ratio,
            height: anchor.y - center.y - (anchor.y - center.y - startOffset.height) * ratio
        )
    }

    static func remotePoint(
        _ location: CGPoint,
        transformedRect: CGRect,
        remoteSize: CGSize
    ) -> (x: UInt16, y: UInt16)? {
        guard transformedRect.contains(location), remoteSize.width > 0, remoteSize.height > 0 else {
            return nil
        }
        let normalizedX = (location.x - transformedRect.minX) / transformedRect.width
        let normalizedY = (location.y - transformedRect.minY) / transformedRect.height
        let x = min(max(Int(normalizedX * remoteSize.width), 0), Int(remoteSize.width) - 1)
        let y = min(max(Int(normalizedY * remoteSize.height), 0), Int(remoteSize.height) - 1)
        return (UInt16(x), UInt16(y))
    }
}
