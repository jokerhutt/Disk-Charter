import SwiftUI

struct WelcomeView: View {
    
    let onContinue: () -> Void
    
    var body: some View {
        VStack {
            Text("👋 Welcome to CleanDifferent")
            Button("Continue", action: onContinue)
        }
    }
    
}
