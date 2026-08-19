import SwiftUI

struct ConnectionView: View {
    @ObservedObject var session: RemoteSessionModel

    @AppStorage("lastHost") private var host = ""
    @AppStorage("lastPort") private var portText = "5900"
    @AppStorage("authenticationMode") private var authenticationMode = AuthenticationMode.macAccount.rawValue
    @AppStorage("lastMacUsername") private var macUsername = ""
    @AppStorage("rememberPassword") private var rememberPassword = true
    @State private var macPassword = ""
    @State private var vncPassword = ""
    @FocusState private var focusedField: Field?

    private enum AuthenticationMode: String, CaseIterable, Identifiable {
        case macAccount
        case vncPassword

        var id: String { rawValue }
        var title: String { self == .macAccount ? "Mac Login" : "VNC Password" }
    }

    private enum Field {
        case host
        case port
        case macUsername
        case macPassword
        case vncPassword
    }

    private var parsedPort: UInt16? {
        UInt16(portText)
    }

    private var canConnect: Bool {
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              parsedPort != nil else { return false }
        if selectedAuthenticationMode == .macAccount {
            return !macUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !macPassword.isEmpty
        }
        return !vncPassword.isEmpty
    }

    private var selectedAuthenticationMode: AuthenticationMode {
        AuthenticationMode(rawValue: authenticationMode) ?? .macAccount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    hero
                    connectionCard
                    securityNote
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 28)
            }
            .background(background)
            .navigationTitle("TailVNC")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: loadSavedCredentials)
            .onChange(of: host) { _, _ in loadSavedCredentials() }
            .onChange(of: portText) { _, _ in loadSavedCredentials() }
            .onChange(of: authenticationMode) { _, _ in loadSavedCredentials() }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.connected.to.line.below")
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)
            Text("Your screen. Your network.")
                .font(.title2.weight(.bold))
            Text("Connect directly to a VNC server over Tailscale or another trusted private network.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var connectionCard: some View {
        VStack(spacing: 18) {
            labeledField("Host", systemImage: "network") {
                TextField("100.x.x.x or MagicDNS name", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focusedField, equals: .host)
                    .accessibilityIdentifier("hostField")
            }

            Divider()

            labeledField("Port", systemImage: "point.3.connected.trianglepath.dotted") {
                TextField("5900", text: $portText)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .port)
                    .accessibilityIdentifier("portField")
            }

            Divider()

            Picker("Authentication", selection: $authenticationMode) {
                ForEach(AuthenticationMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("authenticationPicker")

            Divider()

            if selectedAuthenticationMode == .macAccount {
                labeledField("Mac username", systemImage: "person.fill") {
                    TextField("Account short name", text: $macUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .focused($focusedField, equals: .macUsername)
                        .accessibilityIdentifier("usernameField")
                }

                Divider()

                labeledField("Mac password", systemImage: "key.fill") {
                    SecureField("Mac login password", text: $macPassword)
                        .textContentType(.password)
                        .focused($focusedField, equals: .macPassword)
                        .accessibilityIdentifier("macPasswordField")
                }
            } else {
                labeledField("VNC password", systemImage: "key.fill") {
                    SecureField("VNC-only password", text: $vncPassword)
                        .textContentType(.password)
                        .focused($focusedField, equals: .vncPassword)
                        .accessibilityIdentifier("vncPasswordField")
                }
            }

            Toggle("Remember in Keychain", isOn: $rememberPassword)
                .font(.subheadline.weight(.medium))
                .tint(.cyan)

            Button {
                guard let port = parsedPort else { return }
                focusedField = nil
                let authentication: RFBAuthentication
                if selectedAuthenticationMode == .macAccount {
                    authentication = .macAccount(
                        username: macUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: macPassword
                    )
                } else {
                    authentication = .vncPassword(vncPassword)
                }
                session.connect(
                    host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                    port: port,
                    authentication: authentication,
                    rememberCredentials: rememberPassword
                )
            } label: {
                Label("Connect", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .controlSize(.large)
            .disabled(!canConnect)
            .accessibilityIdentifier("connectButton")

            if let error = session.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("connectionError")
            }
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var securityNote: some View {
        Label {
            if selectedAuthenticationMode == .macAccount {
                Text("Mac Login encrypts your account credentials. Keep the framebuffer private with Tailscale, WireGuard, or SSH.")
            } else {
                Text("VNC Password is legacy compatibility and cannot log in to a locked Mac account. Keep it behind a private tunnel.")
            }
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.green)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private var background: some View {
        ZStack {
            Color(.systemBackground)
            RadialGradient(
                colors: [.cyan.opacity(0.14), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 440
            )
        }
        .ignoresSafeArea()
    }

    private func labeledField<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .foregroundStyle(.cyan)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                content()
            }
        }
    }

    private func loadSavedCredentials() {
        guard rememberPassword, let port = parsedPort, !host.isEmpty else { return }
        if selectedAuthenticationMode == .macAccount {
            if let credentials = session.savedMacCredentials(host: host, port: port) {
                macUsername = credentials.username
                macPassword = credentials.password
            } else {
                macPassword = ""
            }
        } else {
            vncPassword = session.savedPassword(host: host, port: port) ?? ""
        }
    }
}
