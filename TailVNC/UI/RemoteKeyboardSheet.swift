import SwiftUI
import UIKit

struct RemoteKeyboardSheet: View {
    @ObservedObject var session: RemoteSessionModel

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Remote keyboard")
                    .font(.headline)
                Spacer()
                Text("Typing goes to the Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            KeyboardCaptureView(
                onText: session.sendText,
                onDelete: { session.sendKey(0xff08) }
            )
            .frame(height: 44)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.secondary.opacity(0.35))
            }

            HStack(spacing: 10) {
                keyButton("Esc", keysym: 0xff1b)
                keyButton("Tab", keysym: 0xff09)
                keyButton("Return", keysym: 0xff0d)
                keyButton("⌫", keysym: 0xff08)
            }

            HStack(spacing: 10) {
                keyButton("←", keysym: 0xff51)
                keyButton("↑", keysym: 0xff52)
                keyButton("↓", keysym: 0xff54)
                keyButton("→", keysym: 0xff53)
            }
        }
        .padding(20)
    }

    private func keyButton(_ label: String, keysym: UInt32) -> some View {
        Button(label) {
            session.sendKey(keysym)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }
}

private struct KeyboardCaptureView: UIViewRepresentable {
    let onText: (String) -> Void
    let onDelete: () -> Void

    func makeUIView(context: Context) -> CaptureTextField {
        let field = CaptureTextField()
        field.placeholder = "Tap here, then type"
        field.textColor = .label
        field.tintColor = .systemCyan
        field.backgroundColor = .clear
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.returnKeyType = .default
        field.onText = onText
        field.onDelete = onDelete
        field.installInputBridge()
        DispatchQueue.main.async {
            field.becomeFirstResponder()
        }
        return field
    }

    func updateUIView(_ uiView: CaptureTextField, context: Context) {
        uiView.onText = onText
        uiView.onDelete = onDelete
    }
}

final class CaptureTextField: UITextField {
    var onText: ((String) -> Void)?
    var onDelete: (() -> Void)?
    private var isFlushingBufferedText = false

    func installInputBridge() {
        addTarget(self, action: #selector(flushBufferedText), for: .editingChanged)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange(_:)),
            name: UITextField.textDidChangeNotification,
            object: self
        )
    }

    override func insertText(_ text: String) {
        onText?(text)
    }

    override func deleteBackward() {
        onDelete?()
    }

    @objc private func textDidChange(_ notification: Notification) {
        flushBufferedText()
    }

    @objc private func flushBufferedText() {
        guard !isFlushingBufferedText, let value = text, !value.isEmpty else { return }
        isFlushingBufferedText = true
        text = ""
        isFlushingBufferedText = false
        onText?(value)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
