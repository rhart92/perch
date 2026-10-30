import AppKit
import SwiftUI

@MainActor
struct StackNameEditor: NSViewRepresentable {
    let name: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NameField {
        NameField(name: name, onSave: onSave, onCancel: onCancel)
    }

    func updateNSView(_ nsView: NameField, context: Context) {
        // Preserve the draft and selection across PR refreshes.
        nsView.onSave = onSave
        nsView.onCancel = onCancel
    }

    final class NameField: NSTextField, NSTextFieldDelegate {
        private var hasFocused = false
        var onSave: (String) -> Void
        var onCancel: () -> Void

        init(name: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
            self.onSave = onSave
            self.onCancel = onCancel
            super.init(frame: .zero)
            stringValue = name
            placeholderString = "Stack name"
            font = .systemFont(ofSize: 12, weight: .semibold)
            textColor = NSColor(RosePine.text)
            backgroundColor = NSColor(RosePine.surface)
            usesSingleLineMode = true
            delegate = self
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            setAccessibilityLabel("Stack name")
            setAccessibilityIdentifier("stack-name")
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !hasFocused else { return }
            hasFocused = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
                self.selectText(nil)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                validateEditing()
                onSave(stringValue)
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                onCancel()
                return true
            }
            return false
        }
    }
}
