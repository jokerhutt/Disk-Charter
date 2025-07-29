import Foundation

enum ScannerUtils {
    static func checkIfDirectory(_ url: URL) -> Bool {
        do {
            let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
            return resourceValues.isDirectory == true
        } catch {
            print("Error checking if the url is actually a directory: \(error)")
            return false
        }
    }
    
    static func getCurrentDirectoryUrl() -> URL {
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
    
    static func getChildren(of url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }
    
    static func buildFileTreeText(_ node: FileNode, indent: String = "") -> String {
        let marker = node.isDirectory ? "📁" : "📄"
        var result = "\(indent)\(marker) \(node.url.lastPathComponent)\n"

        if let children = node.children {
            for child in children {
                if (child.isDirectory) {
                    result += buildFileTreeText(child, indent: indent + "    ")
                }
            }
        }

        return result
    }
    
    
}
