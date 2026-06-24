import SwiftUI
import UIKit

/// Weight entry that selects all text when focused so typing replaces the whole value.
struct SelectAllWeightField: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onCommit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .decimalPad
        field.textAlignment = .center
        field.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        field.textColor = UIColor(red: 0.961, green: 0.941, blue: 0.910, alpha: 1)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.borderStyle = .none
        field.backgroundColor = .clear
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged), for: .editingChanged)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        if isFocused.wrappedValue, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isFocused.wrappedValue, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: isFocused, onCommit: onCommit)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding var text: String
        var isFocused: FocusState<Bool>.Binding
        var onCommit: () -> Void

        init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, onCommit: @escaping () -> Void) {
            _text = text
            self.isFocused = isFocused
            self.onCommit = onCommit
        }

        @objc func editingChanged(_ sender: UITextField) {
            text = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isFocused.wrappedValue = true
            DispatchQueue.main.async {
                textField.selectAll(nil)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isFocused.wrappedValue = false
            text = textField.text ?? ""
            onCommit()
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
