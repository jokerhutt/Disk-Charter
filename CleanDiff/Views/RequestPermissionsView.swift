import SwiftUI

struct RequestPermissionsView: View {
    @ObservedObject var accessChecker: FullDiskAccessChecker
    let onContinue: () -> Void


    var body: some View {
        VStack(spacing: 20) {
            
            Text(accessChecker.isGranted ? "Access Granted" : "No Access")

        
            Button("Grant Full Disk Access") {
                accessChecker.openSettingsPrompt()
            }
        }
        .onAppear {
            accessChecker.refreshFullDiskAccessStatus()
        }
    }
}


