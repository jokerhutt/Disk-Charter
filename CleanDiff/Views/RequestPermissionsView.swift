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

            Button("List Documents") {
                guard accessChecker.isGranted else {
                    print("Permission not granted.")
                    return
                }

                switch FileService.listDocumentsDirectoryContents() {
                case .success(let files):
                    files.forEach { print("Found: \($0)") }
                case .failure(let error):
                    print("Failed to read directory:", error)
                }
            }
        }
        .onAppear {
            accessChecker.refreshFullDiskAccessStatus()
        }
    }
}


