import SwiftUI

struct DashboardView: View {
    
    let fileService = FileService()
    
    @State private var currentDirectory: URL? = nil
    @State private var fileTreeText: String = ""
    
    @State private var hasScanned: Bool = false
    
    var body: some View {
        VStack {
            Text("Welcome to Disk Storage Manager, David")
            
            if fileTreeText.isEmpty && !hasScanned {
                Button("Print N Nodes deep", action: {
                    hasScanned = true
                    fileTreeText = getFileTreeText()
                })
            }
            
            Button("Print Current Directory", action: {
                currentDirectory = ScannerUtils.getCurrentDirectoryUrl()
            })
            
            if let currentDirectory = currentDirectory {
                Text("Your current directory is: \(currentDirectory.path)")
            }
            
            if fileTreeText.count > 0 {
                Text("\(fileTreeText)")
            }
            
        }
    }
    
    private func getFileTreeText() -> String {
        guard let directory = currentDirectory else { return "" }
        print("directory is: \(directory)")
        let node = Scanner.scanDirectory(
            start: directory, curr: directory, depth: 0, maxDepth: 3)
        
        print("Node url is: \(node.url)")
        
        return ScannerUtils.buildFileTreeText(node)
    }
    
}
