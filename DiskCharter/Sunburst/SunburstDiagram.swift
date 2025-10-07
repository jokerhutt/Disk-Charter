import SwiftUI
import SunburstDiagram

private struct Grouping {
    var keepTopN: Int
    var percent: Double
    var absolute: UInt64
    var maxChildrenPerRing: Int
}

struct FileSystemSunburstView: View {
    let rootFileNode: FileNode
    @StateObject private var configuration: SunburstConfiguration

    private let baseVisibleDepth = 3
    private let deepVisibleDepth = 7
    private static let leafSaturationBoost: CGFloat = 0.12

    init(rootFileNode: FileNode) {
        self.rootFileNode = rootFileNode
        _configuration = StateObject(wrappedValue:
            Self.buildConfiguration(
                focus: rootFileNode,
                visibleDepth: 3
            )
        )
    }
    
    

    var body: some View {
        VStack(spacing: 12) {
            // Header above chart
            Text(headerText)
                .font(.headline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)

            // Chart
            SunburstView(configuration: configuration)
                .drawingGroup()
        }
        .onChange(of: configuration.selectedNode) { _ in
            rebuildForSelection()
        }
    }
    
    private var headerText: String {
        guard let selected = configuration.selectedNode else {
            return "Select a segment"
        }
        // strip the "###path" suffix we encoded into name
        let parts = selected.name.split(separator: "#", maxSplits: 1)
        let displayName = parts.first.map(String.init) ?? "Unknown"

        // In your current code Node.value is GiB already (you divide by 1_073_741_824 when building nodes)
        let gb = selected.value ?? 0
        return String(format: "%@ — %.2f GB", displayName, gb)

        // If you ever switch Node.value back to BYTES, use the line below instead:
        // let gb = (selected.value ?? 0) / 1_073_741_824
    }
    
    private var currentSelectionName: String? {
        guard let selected = configuration.selectedNode else { return nil }
        // Extract original name without the path suffix
        let parts = selected.name.split(separator: "#", maxSplits: 1)
        return parts.first.map(String.init)
    }

    private func rebuildForSelection() {
        guard let sel = configuration.selectedNode else {
            configuration.nodes = Self.buildConfiguration(
                focus: rootFileNode,
                visibleDepth: baseVisibleDepth
            ).nodes
            return
        }
        guard let focus = findFileNode(matching: sel, under: rootFileNode) else { return }
        configuration.nodes = Self.buildConfiguration(
            focus: focus,
            visibleDepth: deepVisibleDepth
        ).nodes
    }

    private static func buildConfiguration(
        focus: FileNode,
        visibleDepth: Int
    ) -> SunburstConfiguration {
        let node = convertToNode(
            fileNode: focus,
            maxDepth: visibleDepth,
            depth: 0,
            parentColor: .clear,
            siblingIndex: 0,
            siblingCount: 1
        )
        return SunburstConfiguration(nodes: [node], calculationMode: .parentIndependent())
    }

    private static func groupingForDepth(_ depth: Int) -> Grouping {
        switch depth {
        case 1: return Grouping(keepTopN: 6, percent: 0.03, absolute: 64*1_048_576, maxChildrenPerRing: 10)
        case 2: return Grouping(keepTopN: 6, percent: 0.04, absolute: 96*1_048_576, maxChildrenPerRing: 10)
        default:return Grouping(keepTopN: 5, percent: 0.06, absolute:192*1_048_576, maxChildrenPerRing: 8)
        }
    }
    
    private static func safeName(_ name: String, path: String) -> String {
        return "\(name)###\(path)"
    }
    
    private static func extractPath(from nodeName: String) -> String? {
        let parts = nodeName.split(separator: "#", maxSplits: 2, omittingEmptySubsequences: false)
        return parts.count >= 3 ? String(parts[2]) : nil
    }
    
    private static func convertToNode(
        fileNode: FileNode,
        maxDepth: Int,
        depth: Int,
        parentColor: NSColor,
        siblingIndex: Int,
        siblingCount: Int
    ) -> Node {
        let myColor: NSColor = {
            if depth == 0 { return .clear }
            if depth == 1 {
                let hue = distinctHue(for: siblingIndex)
                return NSColor(hue: hue, saturation: 0.72, brightness: 0.95, alpha: 1)
            }
            let rotated = parentColor.rotatedHue(by: 0.030 * CGFloat(siblingIndex))
            return rotated.lighten(by: 0.06 * CGFloat(depth))
        }()

        let hasKids = !fileNode.children.isEmpty
        let displayName = safeName(fileNode.name, path: fileNode.path)
        
        // Labels: show names for shallow depths
        let shouldShowName = false
        
        if depth >= maxDepth || !hasKids {
            return Node(
                name: displayName,
                showName: shouldShowName,
                value: Double(fileNode.size) / 1_073_741_824,
                backgroundColor: myColor.boostSaturation(by: leafSaturationBoost)
            )
        }

        let sorted = fileNode.children.sorted { $0.size > $1.size }
        let parentBytes = max(fileNode.size, sorted.reduce(0) { $0 &+ $1.size })

        let g = groupingForDepth(depth + 1)
        var keep: [FileNode] = []
        var fold: [FileNode] = []

        for (idx, c) in sorted.enumerated() {
            if idx < g.keepTopN {
                keep.append(c); continue
            }
            let isSmallAbs = c.size < g.absolute
            let frac = parentBytes == 0 ? 0.0 : Double(c.size) / Double(parentBytes)
            if isSmallAbs || frac < g.percent {
                fold.append(c)
            } else {
                keep.append(c)
            }
        }
        if keep.count > g.maxChildrenPerRing {
            fold.append(contentsOf: keep[g.maxChildrenPerRing...])
            keep.removeSubrange(g.maxChildrenPerRing...)
        }

        var childNodes: [Node] = []
        let childCount = keep.count + (fold.isEmpty ? 0 : 1)

        for (i, child) in keep.enumerated() {
            childNodes.append(convertToNode(
                fileNode: child,
                maxDepth: maxDepth,
                depth: depth + 1,
                parentColor: myColor,
                siblingIndex: i,
                siblingCount: childCount
            ))
        }

        if !fold.isEmpty {
            let otherBytes = fold.reduce(UInt64(0)) { $0 &+ $1.size }
            if otherBytes > 0 {
                childNodes.append(Node(
                    name: safeName("Other", path: fileNode.path + "/Other"),
                    showName: shouldShowName,
                    value: Double(otherBytes) / 1_073_741_824,
                    backgroundColor: myColor.withAlphaComponent(0.22).lighten(by: 0.08)
                ))
            }
        }

        return Node(
            name: displayName,
            showName: shouldShowName,
            value: Double(fileNode.size) / 1_073_741_824,
            backgroundColor: myColor,
            children: childNodes
        )
    }

    private func findFileNode(matching selectedNode: Node, under root: FileNode) -> FileNode? {
        guard let path = Self.extractPath(from: selectedNode.name) else { return nil }
        return findFileNodeByPath(path, under: root)
    }

    private func findFileNodeByPath(_ path: String, under root: FileNode) -> FileNode? {
        if root.path == path { return root }
        for c in root.children {
            if let found = findFileNodeByPath(path, under: c) { return found }
        }
        return nil
    }
}

private func distinctHue(for index: Int) -> CGFloat {
    let phi: CGFloat = 0.618_033_988_75
    let base: CGFloat = 0.08
    return (base + phi * CGFloat(index)).truncatingRemainder(dividingBy: 1)
}

private extension NSColor {
    func rotatedHue(by amount: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        h = (h + amount).truncatingRemainder(dividingBy: 1.0)
        return NSColor(hue: h, saturation: s, brightness: b, alpha: a)
    }
    func lighten(by delta: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: s, brightness: min(1.0, b + delta), alpha: a)
    }
    func boostSaturation(by delta: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else { return self }
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(1.0, s + delta), brightness: b, alpha: a)
    }
}
