import Darwin

class RawFileNode {
    
    let name: String
    let path: String
    let size: Int
    let children: [RawFileNode]?
    
    init(name: String, path: String, size: Int, children: [RawFileNode]? = nil) {
        
        self.name = name
        self.path = path
        self.size = size
        self.children = children
        
    }
    
    func isFile () -> Bool { self.children == nil };
    
    var totalSize: Int {
        (children?.reduce(size) { $0 + $1.totalSize }) ?? size
    }

    var totalItems: Int {
        (children?.reduce(1) { $0 + $1.totalItems }) ?? 1
    }

    var totalFiles: Int {
        (children?.reduce(0) { $0 + $1.totalFiles }) ?? 1
    }

    var totalFolders: Int {
        (children?.reduce(1) { $0 + $1.totalFolders }) ?? 0
    }
    
    
    
    
    
}

extension RawFileNode: Identifiable {
    var id: String { path }  // Use 'path' as the unique identifier
}

extension RawFileNode {
    func pathComponents(upToDepth depth: Int) -> String {
        let components = path.split(separator: "/")
        let prefixDepth = min(depth + 1, components.count)
        return components.prefix(prefixDepth).joined(separator: "/")
    }
}
