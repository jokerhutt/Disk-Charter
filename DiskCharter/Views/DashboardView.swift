import SwiftUI

struct DashboardView: View {
        
    @State private var currentDirectory: String? = nil
    @State private var fileTreeText: String = ""
    
    @State private var hasScanned: Bool = false
    
    var body: some View {
        VStack {
            Text("Welcome to Disk Charter, David")
            
            if fileTreeText.isEmpty && !hasScanned {
                Button("Print N Nodes deep", action: {
                    hasScanned = true
                    fileTreeText = getWalkDir()
                })
            }
            
            Button("Print Current Directory", action: {
                currentDirectory = "/"
            })
            
            if let currentDirectory = currentDirectory {
                Text("Your current directory is: \(currentDirectory)")
            }
            
            if fileTreeText.count > 0 {
                Text("\(fileTreeText)")
            }
            
        }
    }
    
    private func getWalkDir () -> String {
        
        let start = Date()

        let rawWalkClass = WalkRaw()
        
        rawWalkClass.walkTree(path: "/Users/davidglogowski")

        let end = Date()

        let duration = end.timeIntervalSince(start)
        return """
        ⏱ Took \(String(format: "%.2f", duration)) seconds
        """
    }
    
}




