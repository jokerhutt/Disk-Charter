import Foundation
import Darwin
import Atomics


final class ParallelScanner {
    private let taskQueue = BlockingQueue<FileNode>()
    private let dirTaskCount = ManagedAtomic<Int>(0)

    private let includeFiles: Bool
    private let maxDepth: Int
    private let workerCountHint: Int

    init(includeFiles: Bool = true, maxDepth: Int = .max, workerCountHint: Int? = nil) {
        self.includeFiles = includeFiles
        self.maxDepth = maxDepth
        self.workerCountHint = workerCountHint ?? {
            let c = ProcessInfo.processInfo.activeProcessorCount
            return max(1, min(c * 6, c + 16)) // a bit more aggressive than before
        }()
    }

    func startWalk(rootPath: String) -> FileNode {
        let root = FileNode(path: rootPath, type: .directory, parent: nil)
        dirTaskCount.store(1, ordering: .relaxed)
        taskQueue.enqueue(root)

        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)

        for _ in 0..<workerCountHint {
            group.enter()
            queue.async { [weak self] in
                self?.workerLoop()
                group.leave()
            }
        }

        group.wait()
        return root
    }

    private func workerLoop() {
        while let node = taskQueue.dequeue() {
            scanDirectory(node)
        }
    }


    private func scanDirectory(_ dirNode: FileNode) {
        precondition(dirNode.type == .directory)

        if depth(of: dirNode) >= maxDepth {
            attemptFinalizeAndBubble(dirNode)
            maybeCloseQueueAfterDirDone()
            return
        }

        let entries = readChildrenFast(at: dirNode.path)

        dirNode.reserveChildrenCapacity(entries.count)

        var immediateFileBytes: UInt64 = 0
        var directories: [FileNode] = []
        directories.reserveCapacity(entries.count >> 1)

        for m in entries {
            switch m.type {
            case .file:
                if includeFiles {
                    let child = FileNode(path: m.path, type: .file, parent: dirNode)
                    child.storeImmediateSize(m.sizeIfFile) // no extra syscall
                    dirNode.addChild(child)
                }
                immediateFileBytes &+= m.sizeIfFile

            case .directory:
                let child = FileNode(path: m.path, type: .directory, parent: dirNode)
                dirNode.addChild(child)
                directories.append(child)

            case .symlink, .unknown:
                continue
            }
        }

        if immediateFileBytes != 0 {
            dirNode.addToAggregate(immediateFileBytes)
        }

        if !directories.isEmpty {
            dirNode.setPendingDirs(directories.count)
            _ = dirTaskCount.wrappingIncrement(by: directories.count, ordering: .relaxed)
            for d in directories { taskQueue.enqueue(d) }
        } else {
            dirNode.setPendingDirs(0)
        }

        attemptFinalizeAndBubble(dirNode)
        maybeCloseQueueAfterDirDone()
    }

    private func onChildDirectoryFinished(parent: FileNode, childBytes: UInt64) {
        parent.addToAggregate(childBytes)
        let remaining = parent.decrementPendingDirAndLoad()
        if remaining == 0 {
            if let total = parent.finalizeIfNeeded(), let pp = parent.parent {
                onChildDirectoryFinished(parent: pp, childBytes: total)
            }
        }
    }

    private func attemptFinalizeAndBubble(_ node: FileNode) {
        if node.loadPendingDirs() == 0 {
            if let total = node.finalizeIfNeeded(), let p = node.parent {
                onChildDirectoryFinished(parent: p, childBytes: total)
            }
        }
    }

    private func maybeCloseQueueAfterDirDone() {
        let newVal = dirTaskCount.wrappingDecrementThenLoad(ordering: .acquiringAndReleasing)
        if newVal == 0 { taskQueue.close() }
    }


    @inline(__always)
    private func shouldPrune(_ path: String) -> Bool {
        if path.hasPrefix("/private/var/folders") { return true }
        if path.hasPrefix("/System/Volumes/Data/private/var/folders") { return true }
        if path.hasPrefix("/System/Library/Templates") { return true }
        if path.hasPrefix("/System/Volumes/Preboot") { return true }
        if path.hasPrefix("/System/Volumes/Update") { return true }
        if path.hasPrefix("/System/Volumes/VM") { return true }
        if path.hasPrefix("/Library/Developer/CoreSimulator/Volumes") { return true }
        if path == "/dev" { return true }
        return false
    }

    @inline(__always)
    private func canEnter(_ path: String) -> Bool {
        return access(path, X_OK) == 0
    }

    private func readChildrenFast(at path: String) -> [Metadata] {
        var results: [Metadata] = []
        if shouldPrune(path) { return results }
        guard canEnter(path) else { return results }

        guard let dir = opendir(path) else { return results }
        defer { closedir(dir) }

        let dfd = dirfd(dir)
        let needsSlash = (path == "/") ? "" : "/"

        while let ent = readdir(dir) {
            var nameBuf = ent.pointee.d_name
            let namePtr = withUnsafePointer(to: &nameBuf) {
                UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)
            }
            let name = String(cString: namePtr)
            if name == "." || name == ".." { continue }

            var st = stat()
            if fstatat(dfd, namePtr, &st, AT_SYMLINK_NOFOLLOW) != 0 { continue }

            let typeBits = st.st_mode & S_IFMT
            let kind: FileType
            switch typeBits {
            case S_IFREG: kind = .file
            case S_IFDIR: kind = .directory
            case S_IFLNK: kind = .symlink
            default:      kind = .unknown
            }
            if kind == .symlink { continue }

            let fullPath = path + needsSlash + name

            results.append(Metadata(
                path: fullPath,
                type: kind,
                sizeIfFile: (kind == .file) ? UInt64(st.st_size) : 0
            ))
        }
        return results
    }

    @inline(__always)
    private func depth(of node: FileNode) -> Int {
        var d = 0
        var p = node.parent
        while p != nil { d &+= 1; p = p?.parent }
        return d
    }
}
