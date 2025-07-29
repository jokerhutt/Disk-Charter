import Foundation

struct FileNode {
    let url: URL
    let isDirectory: Bool
    let depth: Int
    var children: [FileNode]? // only if isDirectory == true
}
