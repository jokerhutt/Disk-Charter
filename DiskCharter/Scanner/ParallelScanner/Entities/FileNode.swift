import Atomics
import Foundation


final class FileNode {
    let path: String
    let type: FileType
    weak var parent: FileNode?

    private(set) var children: [FileNode] = []

    private let aggregatedSize = ManagedAtomic<UInt64>(0)
    private let pendingChildDirs = ManagedAtomic<Int>(0)
    private let finalized = ManagedAtomic<Bool>(false)

    private let _size = ManagedAtomic<UInt64>(0)
    var size: UInt64 { _size.load(ordering: .relaxed) }

    init(path: String, type: FileType, parent: FileNode? = nil) {
        self.path = path
        self.type = type
        self.parent = parent
    }
    
    @inline(__always)
    func reserveChildrenCapacity(_ n: Int) {
        children.reserveCapacity(n)
    }
    
    var name: String {
        URL(fileURLWithPath: path).lastPathComponent
    }


    @inline(__always)
    func storeImmediateSize(_ bytes: UInt64) {
        _size.store(bytes, ordering: .relaxed)
    }

    @inline(__always)
    func loadPendingDirs() -> Int {
        pendingChildDirs.load(ordering: .relaxed)
    }

    @inline(__always)
    func addChild(_ child: FileNode) {
        children.append(child)
    }

    @inline(__always)
    func addToAggregate(_ bytes: UInt64) {
        _ = aggregatedSize.wrappingIncrement(by: bytes, ordering: .relaxed)
    }

    @inline(__always)
    func setPendingDirs(_ count: Int) {
        pendingChildDirs.store(count, ordering: .relaxed)
    }

    @inline(__always)
    func decrementPendingDirAndLoad() -> Int {
        let newVal = pendingChildDirs.wrappingDecrementThenLoad(ordering: .acquiringAndReleasing)
        return newVal
    }

    @inline(__always)
    func finalizeIfNeeded() -> UInt64? {
        let wasFinalized = finalized.exchange(true, ordering: .acquiringAndReleasing)
        if wasFinalized { return nil }
        let total = aggregatedSize.load(ordering: .relaxed)
        _size.store(total, ordering: .relaxed)
        return total
    }
}
