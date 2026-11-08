import SwiftUI
import UIKit

/// A single-line text field whose return key submits *without* ending editing.
///
/// SwiftUI's `TextField` resigns first responder on return and only gets focus back a moment later; keys
/// typed in that gap are lost ("1 kg apples" → "Kg apples"). UIKit lets `textFieldShouldReturn` say no, so
/// the keyboard never moves and the next item can follow straight away (HANDOFF §2.2).
struct ReturnKeepingTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var textColor: Color = TG.Colors.ink
    var placeholderColor: Color = TG.Colors.ink2
    var tint: Color = TG.Colors.ink
    /// Called with the current text when return is pressed; the field keeps focus.
    var onReturn: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .done
        field.autocapitalizationType = .sentences
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        return field
    }

    /// Takes the offered width but only one line of height (UIKit views otherwise grow to fill).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView field: UITextField, context: Context) -> CGSize? {
        let height = field.intrinsicContentSize.height
        return CGSize(width: proposal.width ?? field.intrinsicContentSize.width, height: height)
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text { field.text = text }
        field.textColor = UIColor(textColor)
        field.tintColor = UIColor(tint)
        field.accessibilityLabel = placeholder
        field.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor(placeholderColor)]
        )
        if isFocused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if !isFocused, field.isFirstResponder {
            DispatchQueue.main.async { field.resignFirstResponder() }
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ReturnKeepingTextField

        init(_ parent: ReturnKeepingTextField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            parent.onReturn(field.text ?? "")
            return false
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }
    }
}
