import SwiftUI
import Charts
import CryptoKit

struct SunburstView: View {
    let chartWidth: CGFloat = 260
    let root: RawFileNode

    @State private var selectedTotal1: Double?
    @State private var selectedSegment1: RawFileNode?
    @State private var selectedTotal2: Double?
    @State private var selectedSegment2: RawFileNode?
    @State private var colorCache: [String: Color] = [:]

    init(root: RawFileNode) {
        self.root = root
        var map: [String: Color] = [:]
        
        let rootDepth = root.path.split(separator: "/").count
        for child in root.children ?? [] {
            let key = pathKey(for: child, depth: rootDepth + 1)
            if map[key] == nil {
                map[key] = deterministicHueColor(for: key)
            }
        }
        
        _colorCache = State(initialValue: map)
    }
    
    let daisyDiskPalette: [Color] = [
        Color(red: 0.91, green: 0.29, blue: 0.23),  // Red
        Color(red: 0.96, green: 0.49, blue: 0.19),  // Orange
        Color(red: 0.95, green: 0.77, blue: 0.06),  // Yellow
        Color(red: 0.18, green: 0.80, blue: 0.44),  // Green
        Color(red: 0.20, green: 0.60, blue: 0.86),  // Blue
        Color(red: 0.61, green: 0.35, blue: 0.71),  // Purple
        Color(red: 0.95, green: 0.43, blue: 0.74),  // Pink
        Color(red: 0.40, green: 0.74, blue: 0.87),  // Light Blue
        Color(red: 0.36, green: 0.60, blue: 0.80),  // Mid Blue
        Color(red: 0.55, green: 0.66, blue: 0.77),  // Steel Blue
        Color(red: 0.30, green: 0.85, blue: 0.64),  // Mint Green
        Color(red: 0.95, green: 0.57, blue: 0.31),  // Peach
        Color(red: 0.75, green: 0.22, blue: 0.17),  // Dark Red
        Color(red: 0.56, green: 0.34, blue: 0.29),  // Brown
        Color(red: 0.85, green: 0.52, blue: 0.56),  // Rose
        Color(red: 0.88, green: 0.81, blue: 0.45)   // Olive Yellow
    ]
    
    func deterministicHueColor(for key: String) -> Color {
        let hash = SHA256.hash(data: Data(key.utf8))
        let bytes = Array(hash)
        let index = Int(bytes[0]) % daisyDiskPalette.count
        return daisyDiskPalette[index]
    }

    func pathKey(for item: RawFileNode, depth: Int) -> String {
        let components = item.path.split(separator: "/").map(String.init)
        if components.count >= depth {
            return components.prefix(depth).joined(separator: "/")
        } else {
            return components.joined(separator: "/")
        }
    }

    func getRing2() -> [RawFileNode] {
        let firstLevelChildren = root.children ?? []
        return firstLevelChildren.flatMap { $0.children ?? [] }
    }

    var body: some View {
        VStack {
            titleView()  // Title above
            chartView()  // Chart below
        }
    }

    @ViewBuilder
    func titleView() -> some View {
        if let segment = selectedSegment1 {
            Text(segment.name)
                .font(.title)
            Text("\(Double(segment.size) / 1_073_741_824, specifier: "%.2f") GB")
                .font(.title3)
        } else if let segment = selectedSegment2 {
            Text(segment.name)
                .font(.title)
            Text("\(Double(segment.size) / 1_073_741_824, specifier: "%.2f") GB")
                .font(.title3)
        } else {
            Text("Welcome to Disk Charter!")
                .font(.title)
            Text("Select a segment...")
                .font(.title3)
        }
    }

    @ViewBuilder
    func chartView() -> some View {
        let nodes = root.children ?? []
        let ring2Nodes = getRing2()

        ZStack {
            // RING 2 (Outer Ring)
            let outerRing = getRing2()
            Chart(outerRing, id: \.id) { item in
                SectorMark(
                    angle: .value("Size", item.totalSize),
                    innerRadius: .ratio(0.6),
                    outerRadius: .ratio(0.9),
                    angularInset: 1.5
                )
                .foregroundStyle(explicitColor(for: item)
                    .opacity(opacity(for: item, ring: 2)))
            }
            .frame(width: chartWidth * 2, height: chartWidth * 2)  // Full frame size
            .chartAngleSelection(value: $selectedTotal2)
            .onChange(of: selectedTotal2) { _, newValue in
                if let newValue {
                    selectedSegment2 = findSelectedSector(value: newValue, in: outerRing)
                    selectedSegment1 = nil
                } else {
                    selectedSegment2 = nil
                }
            }

            // RING 1 (Inner Ring)
            let innerRing = root.children ?? []
            Chart(innerRing, id: \.id) { item in
                SectorMark(
                    angle: .value("Size", item.totalSize),
                    innerRadius: .ratio(0.5),
                    angularInset: 1.5
                )
                .foregroundStyle(explicitColor(for: item)
                    .boostBrightnessAndSaturation(by: 0.6)
                    .opacity(opacity(for: item, ring: 2)))
            }
            .frame(width: chartWidth, height: chartWidth)  // Shrink frame to actual sector size
            .chartAngleSelection(value: $selectedTotal1)
            .onChange(of: selectedTotal1) { _, newValue in
                if let newValue {
                    selectedSegment1 = findSelectedSector(value: newValue, in: innerRing)
                    selectedSegment2 = nil
                } else {
                    selectedSegment1 = nil
                }
            }
        }
        .frame(width: chartWidth * 2, height: chartWidth * 2)
    }

    func explicitColor(for item: RawFileNode) -> Color {
        let rootDepth = root.path.split(separator: "/").count
        let components = item.path.split(separator: "/").map(String.init)
        let depth = components.count - rootDepth  // Depth relative to root node

        let baseKey = pathKey(for: item, depth: rootDepth + 1)
        guard let baseColor = colorCache[baseKey] else {
            let hash = SHA256.hash(data: Data(item.path.utf8))
            let bytes = Array(hash)
            let r = Double(bytes[0]) / 255.0
            let g = Double(bytes[1]) / 255.0
            let b = Double(bytes[2]) / 255.0
            return Color(red: r, green: g, blue: b)
        }

        // LIGHTEN RING 2 (Outer Ring) - if depth >= 2, lighten!
        if depth >= 2 {
            return lightenColor(baseColor, by: 0.1)  // brighten by 30%
        }

        return baseColor  // Inner ring stays as is
    }
    
    func lightenColor(_ color: Color, by amount: Double) -> Color {
        let clampedAmount = min(max(amount, 0), 1)

        guard let nsColor = NSColor(color).usingColorSpace(.deviceRGB) else { return color }

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        nsColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        // Move each component towards white
        r = r + (1.0 - r) * clampedAmount
        g = g + (1.0 - g) * clampedAmount
        b = b + (1.0 - b) * clampedAmount

        return Color(red: Double(r), green: Double(g), blue: Double(b), opacity: Double(a))
    }

    func opacity(for item: RawFileNode, ring: Int) -> Double {
        if ring == 1 && item.id == selectedSegment1?.id {
            return 1.0
        } else if ring == 2 && item.id == selectedSegment2?.id {
            return 1.0
        } else {
            return 0.8
        }
    }

    func findSelectedSector(value: Double, in data: [RawFileNode]) -> RawFileNode? {
        var accumulated: Double = 0
        for item in data {
            accumulated += Double(item.totalSize)
            if value <= accumulated {
                return item
            }
        }
        return nil
    }
}

extension Color {
    func boostBrightnessAndSaturation(by factor: Double) -> Color {
        guard factor >= 0 && factor <= 1 else { return self }

        guard let nsColor = NSColor(self).usingColorSpace(.deviceRGB) else { return self }

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0

        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let boostedSaturation = min(saturation + factor, 1.0)
        let boostedBrightness = min(brightness + factor, 1.0)

        return Color(hue: Double(hue), saturation: Double(boostedSaturation), brightness: Double(boostedBrightness))
    }
}
