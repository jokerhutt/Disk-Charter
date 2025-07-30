import SwiftUI

struct ContentView: View {
    @State private var phase: AppPhase = .welcome
    
    
    @StateObject private var accessChecker = FullDiskAccessChecker()
    
    var body: some View {
        ZStack {
        
            VisualEffectBlur()
                .ignoresSafeArea() // Covers entire window

            Color.white.opacity(0.05)
                .ignoresSafeArea()
            
            switch phase {
            case .welcome:
                WelcomeView(onContinue: { evaluateAccessStatus() })
            case .requestPermission:
                RequestPermissionsView(accessChecker: accessChecker, onContinue: { phase = .dashboard })
            case .dashboard:
                DashboardView()
            }
        }
        
    }
    
    private func evaluateAccessStatus() {
        accessChecker.refreshFullDiskAccessStatus()

        if accessChecker.isGranted {
            phase = .dashboard
        } else {
            phase = .requestPermission
        }
    }
    
}



