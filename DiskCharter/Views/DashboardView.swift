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
                    Task {
                        fileTreeText = await getWalkDir()
                    }
                })
            }
            
            Button("Print Current Directory", action: {
                currentDirectory = "/"
            })
            
            if let currentDirectory = currentDirectory {
                Text("Your current directory is: \(currentDirectory)")
            }
            
            if fileTreeText.count > 0 {
                Text(fileTreeText)
                    .font(.system(.body, design: .monospaced)) // Optional: monospaced for alignment
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }
    
    private func getWalkDir() async -> String {
        await withCheckedContinuation { continuation in
            let start = Date()

            let rawWalkClass = WalkRaw()
            rawWalkClass.start(path: "/") { root in
                let end = Date()
                let duration = end.timeIntervalSince(start)

                guard let root = root, let children = root.children else {
                    continuation.resume(returning: "❌ Failed to scan /")
                    return
                }

                var result = "Top-level directories under /\n"

                for child in children {
                    let sizeInGB = Double(child.size) / 1_073_741_824  // GB
                    let namePadded = child.name.padding(toLength: 25, withPad: " ", startingAt: 0)
                    result += "\(namePadded) \(String(format: "%8.2f", sizeInGB)) GB\n"
                }

                let durationStr = String(format: "%.2f", duration)
                result += "\n⏱ Took \(durationStr) seconds"

                continuation.resume(returning: result)
            }
        }
    }
}
