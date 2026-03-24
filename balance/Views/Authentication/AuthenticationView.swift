import SwiftUI

struct AuthenticationView: View {
    @State private var showSignUp = false
    
    var body: some View {
        Group {
            if showSignUp {
                UltimateSignUpView(onSignIn: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showSignUp = false
                    }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            } else {
                UltimateLoginView(onSignUp: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showSignUp = true
                    }
                })
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
            }
        }
    }
}
