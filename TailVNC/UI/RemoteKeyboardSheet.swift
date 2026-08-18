import SwiftUI
import UIKit

struct KeyboardCaptureView: UIViewRepresentable {
    let isActive: Bool
    let onText: (String) -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void

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
        field.onReturn = onReturn
        field.installInputBridge()
        return field
    }

    func updateUIView(_ uiView: CaptureTextField, context: Context) {
        uiView.onText = onText
        uiView.onDelete = onDelete
        uiView.onReturn = onReturn
        DispatchQueue.main.async {
            if isActive, !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            } else if !isActive, uiView.isFirstResponder {
                uiView.resignFirstResponder()
            }
        }
    }
}

final class CaptureTextField: UITextField {
    var onText: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onReturn: (() -> Void)?
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
        if text == "\n" || text == "\r" {
            onReturn?()
            return
        }
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
