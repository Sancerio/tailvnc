import SwiftUI

struct ConnectionView: View {
    @ObservedObject var session: RemoteSessionModel

    @AppStorage("lastHost") private var host = ""
    @AppStorage("lastPort") private var portText = "5900"
    @AppStorage("rememberPassword") private var rememberPassword = true
    @State private var password = ""
    @FocusState private var focusedField: Field?

    private enum Field {
        case host
        case port
        case password
    }

    private var parsedPort: UInt16? {
        UInt16(portText)
    }

    private var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && parsedPort != nil
            && !password.isEmpty
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
            .onAppear(perform: loadSavedPassword)
            .onChange(of: host) { _, _ in loadSavedPassword() }
            .onChange(of: portText) { _, _ in loadSavedPassword() }
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

            labeledField("VNC password", systemImage: "key.fill") {
                SecureField("Required", text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .accessibilityIdentifier("passwordField")
            }

            Toggle("Remember in Keychain", isOn: $rememberPassword)
                .font(.subheadline.weight(.medium))
                .tint(.cyan)

            Button {
                guard let port = parsedPort else { return }
                focusedField = nil
                session.connect(
                    host: host.trimmingCharacters(in: .whitespacesAndNewlines),
                    port: port,
                    password: password,
                    rememberPassword: rememberPassword
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
            Text("Classic VNC is not encrypted. Keep port 5900 private and connect through Tailscale, WireGuard, or SSH.")
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

    private func loadSavedPassword() {
        guard rememberPassword, let port = parsedPort, !host.isEmpty else { return }
        password = session.savedPassword(host: host, port: port) ?? ""
    }
}
