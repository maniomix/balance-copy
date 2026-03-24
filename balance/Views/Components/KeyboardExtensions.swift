import SwiftUI

// MARK: - Global Keyboard Dismiss
extension View {
    /// Adds a "Done" button above keyboard and tap-to-dismiss functionality
    func dismissKeyboardOnTap() -> some View {
        self
            .onTapGesture {
                hideKeyboard()
            }
    }
    
    /// Adds keyboard toolbar with Done button
    func keyboardDoneButton() -> some View {
        self
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        hideKeyboard()
                    }
                    .foregroundColor(.blue)
                }
            }
    }
    
    /// Complete keyboard management (toolbar + tap to dismiss)
    func keyboardManagement() -> some View {
        self
            .keyboardDoneButton()
            .dismissKeyboardOnTap()
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
