import Foundation
import Darwin
import Atomics


final class ParallelScanner {
    private let taskQueue = BlockingQueue<FileNode>()
    private let dirTaskCount = ManagedAtomic<Int>(0)

    // Tunables
    private let includeFiles: Bool
    private let maxDepth: Int
    private let workerCountHint: Int

    enum OpaqueBundlePolicy { case skip, aggregate /*, descend */ }

    private let opaquePolicy: OpaqueBundlePolicy

    /// Set `includeFiles` to false for a big speedup if you only chart folders.
    /// `opaquePolicy: .aggregate` ensures bundles like .app contribute their full recursive size.
    init(
        includeFiles: Bool = false,
        maxDepth: Int = .max,
        workerCountHint: Int? = nil,
        opaquePolicy: OpaqueBundlePolicy = .aggregate
    ) {
        self.includeFiles = includeFiles
        self.maxDepth = maxDepth
        self.opaquePolicy = opaquePolicy
        let c = ProcessInfo.processInfo.activeProcessorCount
        // Slightly more aggressive; adjust if you see context-switch spikes.
        self.workerCountHint = workerCountHint ?? max(1, min(c * 8, c + 24))
    }

    func startWalk(rootPath: String) -> FileNode {
        let root = FileNode(path: rootPath, type: .directory, parent: nil, depth: 0)
        dirTaskCount.store(1, ordering: .relaxed)
        taskQueue.enqueue(root)

        let group = DispatchGroup()
        let q = DispatchQueue.global(qos: .userInitiated)

        for _ in 0..<workerCountHint {
            group.enter()
            q.async { [weak self] in self?.workerLoop(); group.leave() }
        }

        group.wait()
        return root
    }

    private func workerLoop() {
        while let node = taskQueue.dequeue() {
            autoreleasepool { scanDirectory(node) }
        }
    }
    
    private func scanDirectory(_ dirNode: FileNode) {
        precondition(dirNode.type == .directory)

        if dirNode.depth >= maxDepth {
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
                    let child = FileNode(path: m.path, type: .file, parent: dirNode, depth: dirNode.depth + 1)
                    child.storeImmediateSize(m.sizeIfFile)
                    dirNode.addChild(child)
                }
                immediateFileBytes &+= m.sizeIfFile

            case .directory:

                if isOpaqueBundlePath(m.path) {
                    switch opaquePolicy {
                    case .skip:
                        if includeFiles {
                            let child = FileNode(path: m.path, type: .directory, parent: dirNode, depth: dirNode.depth + 1)
                            dirNode.addChild(child)
                        }

                        continue

                    case .aggregate:

                        let bytes = aggregateDirectoryBytesOpaque(at: m.path)
                        if includeFiles {
                            let child = FileNode(path: m.path, type: .directory, parent: dirNode, depth: dirNode.depth + 1)
                            child.storeImmediateSize(bytes)
                            dirNode.addChild(child)
                        }
                        if bytes != 0 { dirNode.addToAggregate(bytes) }
                        continue

                    }
                }

                let child = FileNode(path: m.path, type: .directory, parent: dirNode, depth: dirNode.depth + 1)
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
            taskQueue.enqueueMany(directories)
        } else {
            dirNode.setPendingDirs(0)
        }

        attemptFinalizeAndBubble(dirNode)
        maybeCloseQueueAfterDirDone()
    }

    private func onChildDirectoryFinished(parent: FileNode, childBytes: UInt64) {
        parent.addToAggregate(childBytes)
        if parent.decrementPendingDirAndLoad() == 0 {
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
        if dirTaskCount.wrappingDecrementThenLoad(ordering: .acquiringAndReleasing) == 0 {
            taskQueue.close()
        }
    }

    @inline(__always)
    private func aggregateDirectoryBytesOpaque(at root: String) -> UInt64 {
        var total: UInt64 = 0
        var stack: [String] = [root]

        while let path = stack.popLast() {
            guard let dir = opendir(path) else { continue }
            let dfd = dirfd(dir)
            let needsSlash = (path == "/") ? "" : "/"
            defer { closedir(dir) }

            while let ent = readdir(dir) {
                var nameBuf = ent.pointee.d_name
                let namePtr = withUnsafePointer(to: &nameBuf) {
                    UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self)
                }
                // skip "." and ".." cheaply
                if namePtr.pointee == 46 {
                    let c1 = (namePtr + 1).pointee
                    if c1 == 0 || (c1 == 46 && (namePtr + 2).pointee == 0) { continue }
                }

                var st = stat()
                if fstatat(dfd, namePtr, &st, AT_SYMLINK_NOFOLLOW) != 0 { continue }
                let mode = st.st_mode & S_IFMT
                switch mode {
                case S_IFREG:
                    total &+= UInt64(st.st_size)
                case S_IFDIR:
                    let name = String(cString: namePtr)
                    stack.append(path + needsSlash + name)
                default:
                    continue
                }
            }
        }
        return total
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
    private func isOpaqueBundlePath(_ path: String) -> Bool {

        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "app", "framework", "bundle", "plugin", "kext", "appex", "xpc",
             "scptd", "qlgenerator", "wdgt", "lproj", "xcassets",
             "xcframework", "xcarchive", "dSYM", "pkg":
            return true
        default:
            return false
        }
    }

    @inline(__always)
    private func canEnter(_ path: String) -> Bool {
        access(path, X_OK) == 0
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
            if namePtr.pointee == 46 {
                let c1 = (namePtr + 1).pointee
                if c1 == 0 || (c1 == 46 && (namePtr + 2).pointee == 0) { continue }
            }

            var st = stat()
            if fstatat(dfd, namePtr, &st, AT_SYMLINK_NOFOLLOW) != 0 { continue }

            let mode = st.st_mode & S_IFMT
            if mode == S_IFLNK { continue }

            let kind: FileType
            switch mode {
            case S_IFREG: kind = .file
            case S_IFDIR: kind = .directory
            default:      kind = .unknown
            }
            if kind == .unknown { continue }

            // Build full path lazily only now
            let name = String(cString: namePtr)
            let fullPath = path + needsSlash + name

            results.append(Metadata(
                path: fullPath,
                type: kind,
                sizeIfFile: (kind == .file) ? UInt64(st.st_size) : 0
            ))
        }
        return results
    }
}
