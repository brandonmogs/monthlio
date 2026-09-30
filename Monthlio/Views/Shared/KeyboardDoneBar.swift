import SwiftUI
import UIKit

extension View {
    /// A Done button above the keyboard: the decimal pad has no return key,
    /// so amount fields otherwise trap the keyboard until a tap elsewhere.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .font(.body.weight(.semibold))
            }
        }
    }
}
