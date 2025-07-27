import SwiftUI

struct ContentView: View {
    @StateObject private var accessChecker = FullDiskAccessChecker()

    var body: some View {
        
        ZStack {
            
            Image("MenuBackgroundImage")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                
                Text(accessChecker.isGranted ? "✅ Access Granted" : "❌ No Access")

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
        }
        .onAppear {
            accessChecker.refreshFullDiskAccessStatus()
        }
    }
}
