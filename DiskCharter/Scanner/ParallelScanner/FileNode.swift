final class FileNode {
    let path: String
    let type: FileType

    private var _size = ManagedAtomic<UInt64>(0)
    private var _children = [FileNode]()
    private let childrenLock = NSLock()

    var size: UInt64 { _size.load(ordering: .relaxed) }

    init(path: String, type: FileType) {
        self.path = path
        self.type = type
    }

    func addChild(_ child: FileNode) {
        childrenLock.lock()
        _children.append(child)
        childrenLock.unlock()
    }

    func getChildren() -> [FileNode] {
        childrenLock.lock()
        let copy = _children
        childrenLock.unlock()
        return copy
    }

    func setSize(_ newSize: UInt64) {
        _size.store(newSize, ordering: .relaxed)
    }
}
