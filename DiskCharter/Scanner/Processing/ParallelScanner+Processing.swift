
extension ParallelScanner {
    
    func addChildDirectoryNode (parentNode: FileNode, path: String) -> FileNode {
        
        let child = FileNode(path: path, type: .directory, parent: parentNode, depth: parentNode.depth + 1)
        parentNode.addChild(child)
        return child;
    }
    
    func addChildFileNode (parentNode: FileNode, metaData: Metadata) {
        let child = FileNode(path: metaData.path, type: .file, parent: parentNode, depth: parentNode.depth + 1)
        child.storeImmediateSize(metaData.sizeIfFile)
        parentNode.addChild(child)
    }
    
    func addFileBytes(_ current: inout UInt64, meta: Metadata) {
        current &+= meta.sizeIfFile
    }
    
    
    
}
