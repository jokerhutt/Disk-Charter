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

        let scanner = ParallelScanner()
        let root = scanner.startWalk(rootPath: "/")

        // 1-layer deep print
        print("\n===== TOP LEVEL ONLY =====")
        for child in root.children {
            let sizeGB = Double(child.size) / 1_073_741_824
            print("📦 \(child.name) — \(String(format: "%.2f", sizeGB)) GB")
        }
        print("==========================\n")

        let duration = Date().timeIntervalSince(start)
        print("⏱ Took \(String(format: "%.2f", duration)) seconds")

        // If you still want text output in the view:
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
    
//    private func scanAndShowSunburst() async {
//        let start = Date()
//
//        let batchScannerClass = BatchScanner()
//        if let root = await batchScannerClass.start(path: "/Users/davidglogowski/Documents") {
//            let groupedRoot = groupSmallChildren(node: root, thresholdBytes: 100 * 1_048_576) // 100 MB
//
//            self.rootNode = groupedRoot
//
//            print("\n===== FULL SCAN TREE =====")
//            func printRecursive(_ node: RawFileNode, indent: String = "") {
//                let sizeGB = Double(node.size) / 1_073_741_824
//                print("\(indent)📦 \(node.name) — \(String(format: "%.2f", sizeGB)) GB")
//                for child in node.children ?? [] {
//                    printRecursive(child, indent: indent + "    ")
//                }
//            }
//            printRecursive(groupedRoot)
//            print("===== END OF TREE =====\n")
//
//            var result = "Top-level directories under /\n"
//            for child in groupedRoot.children ?? [] {
//                let sizeInGB = Double(child.size) / 1_073_741_824
//                let namePadded = child.name.padding(toLength: 25, withPad: " ", startingAt: 0)
//                result += "\(namePadded) \(String(format: "%8.2f", sizeInGB)) GB\n"
//            }
//
//            let duration = Date().timeIntervalSince(start)
//            let durationStr = String(format: "%.2f", duration)
//            result += "\n⏱ Took \(durationStr) seconds"
//
//            self.fileTreeText = result
//        } else {
//            self.fileTreeText = "❌ Failed to scan /"
//        }
//    }
    
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


