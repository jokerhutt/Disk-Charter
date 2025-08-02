import SwiftUI

struct DashboardView: View {
        
    @State private var currentDirectory: String? = nil
    @State private var fileTreeText: String = ""
    @State private var rootNode: RawFileNode? = nil
    @State private var hasScanned: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to Disk Charter, David")
                .font(.title)
            
            if fileTreeText.isEmpty && !hasScanned {
                Button("Start Scan") {
                    hasScanned = true
                    Task {
                        await scanAndShowSunburst()
                    }
                }
            }
            
            if let rootNode = rootNode {
                HStack(alignment: .center, spacing: 100) {  // <-- Spacing between ScrollView and SunburstView
                    ScrollView(.vertical) {
                        Text(fileTreeText)
                            .font(.system(.body, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxHeight: 400)
                    }
                    .frame(width: 400, height: 400)

                    VStack {
                        SunburstView(root: rootNode)
                            .frame(width: 300)  // Don't constrain height here
                        Spacer(minLength: 0)  // Pushes SunburstView up if needed
                    }
                    .frame(height: 400)  // Matches ScrollView height, aligns center
                }
                .frame(maxWidth: 1200, alignment: .leading)
                .padding()
            }
        }
        .padding()
    }
    
    private func scanAndShowSunburst() async {
        let start = Date()
        
        let rawWalkClass = WalkRaw()
        if let root = await rawWalkClass.start(path: "/Users/davidglogowski/codemain") {
            self.rootNode = root  // Update SunburstView trigger
            
            var result = "Top-level directories under /\n"
            for child in root.children ?? [] {
                let sizeInGB = Double(child.size) / 1_073_741_824  // GB
                let namePadded = child.name.padding(toLength: 25, withPad: " ", startingAt: 0)
                result += "\(namePadded) \(String(format: "%8.2f", sizeInGB)) GB\n"
            }
            
            let duration = Date().timeIntervalSince(start)
            let durationStr = String(format: "%.2f", duration)
            result += "\n⏱ Took \(durationStr) seconds"
            
            self.fileTreeText = result
        } else {
            self.fileTreeText = "❌ Failed to scan /"
        }
    }
}
