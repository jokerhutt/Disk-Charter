import SwiftUI

struct DashboardView: View {
    
    var body: some View {
        VStack {
            Text("Welcome to CleanDifferent, David")
            Button("Start your Scan", action: {
                print("hi")
            })
        }
    }
    
}
