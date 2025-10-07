import SwiftUI

struct DashboardView: View {
        
    @State private var currentDirectory: String? = nil
    @State private var fileTreeText: String = ""
    @State private var rootNode: FileNode? = nil
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
                HStack(alignment: .center, spacing: 100) {
                    ScrollView(.vertical) {
                        Text(fileTreeText)
                            .font(.system(.body, design: .monospaced))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxHeight: 400)
                    }

                    FileSystemSunburstView(rootFileNode: rootNode)
                }
                .frame(maxWidth: 1600, alignment: .leading)
                .padding()
            }
        }
        .padding()
    }
    
    private func scanAndShowSunburst() async {
        let start = Date()

        // Tune scanner as you like (these defaults are fine)
        let scanner = ParallelScanner()
        let root = scanner.startWalk(rootPath: "/")

        // Make the chart use FileNode directly
        self.rootNode = root

        // Optional: 1-layer printout for debugging
        print("\n===== TOP LEVEL ONLY =====")
        for child in root.children {
            let sizeGB = Double(child.size) / 1_073_741_824
            print("📦 \(child.name) — \(String(format: "%.2f", sizeGB)) GB")
        }
        print("==========================\n")

        let duration = Date().timeIntervalSince(start)
        print("⏱ Took \(String(format: "%.2f", duration)) seconds")

        var result = "Top-level directories under \(root.path)\n"
        for child in root.children {
            let sizeInGB = Double(child.size) / 1_073_741_824
            let namePadded = URL(fileURLWithPath: child.path).lastPathComponent
                .padding(toLength: 25, withPad: " ", startingAt: 0)
            result += "\(namePadded) \(String(format: "%8.2f", sizeInGB)) GB\n"
        }
        result += "\n⏱ Took \(String(format: "%.2f", duration)) seconds"
        self.fileTreeText = result
    }
    
    private func groupSmallChildren(node: RawFileNode, thresholdBytes: Int) -> RawFileNode {
        guard let children = node.children else { return node }

        var large: [RawFileNode] = []
        var small: [RawFileNode] = []

        for child in children {
            if child.size < thresholdBytes {
                small.append(child)
            } else {
                large.append(groupSmallChildren(node: child, thresholdBytes: thresholdBytes))
            }
        }

        var newChildren = large

        if !small.isEmpty {
            let totalSize = small.reduce(0) { $0 + $1.size }
            let otherNode = RawFileNode(
                name: "Other",
                path: node.path + "/Other",
                size: totalSize,
                children: nil
            )
            newChildren.append(otherNode)
        }

        let newTotalSize = newChildren.reduce(0) { $0 + $1.size }

        return RawFileNode(
            name: node.name,
            path: node.path,
            size: newTotalSize,
            children: newChildren.isEmpty ? nil : newChildren
        )
    }
    
    
}


