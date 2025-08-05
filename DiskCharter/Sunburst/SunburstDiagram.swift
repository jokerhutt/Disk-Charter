import SwiftUI
import SunburstDiagram  // Package

struct FileSystemSunburstView: View {
    let rootFileNode: RawFileNode  // <-- You pass it dynamically!

    var body: some View {
        let rootNode = convertToNode(rawNode: rootFileNode, baseColor: NSColor.systemBlue)
        let configuration = SunburstConfiguration(nodes: [rootNode], calculationMode: .parentIndependent())

        SunburstView(configuration: configuration)
    }

    private func convertToNode(rawNode: RawFileNode, baseColor: NSColor, depth: Int = 0) -> Node {
        let adjustedColor = baseColor.blended(withFraction: CGFloat(depth) * 0.05, of: .white) ?? baseColor

        if let children = rawNode.children, !children.isEmpty {
            let childNodes = children.enumerated().map { (index, childRawNode) -> Node in
                let hueShift = CGFloat(index) * 0.03
                let shiftedColor = adjustedColor.usingColorSpace(.deviceRGB)?.rotatedHue(by: hueShift) ?? adjustedColor
                return convertToNode(rawNode: childRawNode, baseColor: shiftedColor, depth: depth + 1)
            }
            return Node(
                name: rawNode.name,
                value: nil,
                backgroundColor: adjustedColor,
                children: childNodes
            )
        } else {
            return Node(
                name: rawNode.name,
                value: Double(rawNode.size),
                backgroundColor: adjustedColor
            )
        }
    }
}

extension NSColor {
    func rotatedHue(by amount: CGFloat) -> NSColor {
        guard let rgb = usingColorSpace(.deviceRGB) else { return self }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        hue = (hue + amount).truncatingRemainder(dividingBy: 1.0)
        return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: alpha)
    }
}

#if DEBUG
struct FileSystemSunburstView_Previews: PreviewProvider {
    static var previews: some View {
        let testRoot = RawFileNode(
            name: "Root",
            path: "/",
            size: 0,
            children: [
                RawFileNode(name: "System", path: "/System", size: 3000, children: [
                    RawFileNode(name: "Library", path: "/System/Library", size: 2000),
                    RawFileNode(name: "Extensions", path: "/System/Extensions", size: 1000)
                ]),
                RawFileNode(name: "Users", path: "/Users", size: 5000, children: [
                    RawFileNode(name: "david", path: "/Users/david", size: 3000),
                    RawFileNode(name: "esme", path: "/Users/esme", size: 2000)
                ]),
                RawFileNode(name: "Applications", path: "/Applications", size: 4000)
            ]
        )

        FileSystemSunburstView(rootFileNode: testRoot)
            .frame(width: 600, height: 600)
            .previewLayout(.sizeThatFits)
    }
}
#endif
