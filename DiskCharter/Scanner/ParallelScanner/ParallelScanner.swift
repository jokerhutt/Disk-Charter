import Foundation
import Darwin
import Atomics

private struct DevIno: Hashable {
    let dev: UInt64
    let ino: UInt64
}

private final class ShardedVisited {
    private final class Bucket {
        let lock = NSLock()
        var set = Set<DevIno>()
    }
    private let buckets: [Bucket]
    private let mask: Int

    init(capacityPowerOfTwo: Int = 64) {
        let count = max(16, capacityPowerOfTwo).nextPowerOfTwo()
        var tmp: [Bucket] = []
        tmp.reserveCapacity(count)
        for _ in 0..<count { tmp.append(Bucket()) }
        buckets = tmp
        mask = count - 1
    }

    @inline(__always)
    private func index(for key: DevIno) -> Int {
        var h = key.dev &* 0x9E3779B185EBCA87 &+ key.ino
        h ^= h >> 33
        h &*= 0xff51afd7ed558ccd
        return Int(truncatingIfNeeded: h) & mask
    }

    @inline(__always)
    func insert(_ key: DevIno) -> Bool {
        let i = index(for: key)
        let b = buckets[i]
        b.lock.lock()
        let inserted = b.set.insert(key).inserted
        b.lock.unlock()
        return inserted
    }
}

private extension Int {
    func nextPowerOfTwo() -> Int {
        var v = self - 1
        v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16
        #if arch(arm64) || arch(x86_64)
        v |= v >> 32
        #endif
        return v + 1
    }
}


final class ParallelScanner {
    private let taskQueue = BlockingQueue<FileNode>()
    private let dirTaskCount = ManagedAtomic<Int>(0)

    enum SizeKind { case allocated, logical }
    enum OpaqueBundlePolicy { case skip, aggregate /*, descend */ }

    private let includeFiles: Bool
    private let maxDepth: Int
    private let workerCountHint: Int
    private let sizeKind: SizeKind
    private let opaquePolicy: OpaqueBundlePolicy
    private let stayOnDevice: Bool

    private var rootDev: UInt64 = 0
    private let visited = ShardedVisited(capacityPowerOfTwo: 128)

    init(
        includeFiles: Bool = false,
        maxDepth: Int = .max,
        workerCountHint: Int? = nil,
        sizeKind: SizeKind = .allocated,
        opaquePolicy: OpaqueBundlePolicy = .aggregate,
        stayOnDevice: Bool = true
    ) {
        self.includeFiles = includeFiles
        self.maxDepth = maxDepth
        self.sizeKind = sizeKind
        self.opaquePolicy = opaquePolicy
        self.stayOnDevice = stayOnDevice
        let c = ProcessInfo.processInfo.activeProcessorCount
        self.workerCountHint = workerCountHint ?? max(1, min(c * 8, c + 24))
    }

    func startWalk(rootPath: String) -> FileNode {
        var st = stat()
        if lstat(rootPath, &st) == 0 {
            rootDev = devU64(st.st_dev)
        }

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

        let entries = readChildrenFast(at: dirNode.path, parentDepth: dirNode.depth)

        dirNode.reserveChildrenCapacity(entries.count)
        var immediateFileBytes: UInt64 = 0

        var directories: [FileNode] = []
        directories.reserveCapacity(entries.count >> 1)

        for m in entries {
            let key = DevIno(dev: m.dev, ino: m.ino)

            switch m.type {
            case .file:
                if visited.insert(key) {
                    immediateFileBytes &+= m.sizeIfFile
                }
                if includeFiles {
                    let child = FileNode(path: m.path, type: .file, parent: dirNode, depth: dirNode.depth + 1)
                    child.storeImmediateSize(m.sizeIfFile)
                    dirNode.addChild(child)
                }

            case .directory:
                if !visited.insert(key) { continue }

                if shouldPruneTopLevelSystem(dirNode: dirNode, childPath: m.path) {
                    continue
                }

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

        if immediateFileBytes != 0 { dirNode.addToAggregate(immediateFileBytes) }

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
    private func shouldPruneTopLevelSystem(dirNode: FileNode, childPath: String) -> Bool {
        if dirNode.depth == 0 && dirNode.path == "/" && childPath == "/System" {
            return true
        }
        return false
    }

    @inline(__always)
    private func isOpaqueBundlePath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "app", "framework", "bundle", "plugin", "kext", "appex", "xpc",
             "scptd", "qlgenerator", "wdgt", "lproj", "xcassets",
             "xcframework", "xcarchive", "dsym", "pkg":
            return true
        default:
            return false
        }
    }

    @inline(__always)
    private func canEnter(_ path: String) -> Bool {
        access(path, X_OK) == 0
    }

    @inline(__always)
    private func bytes(for st: stat) -> UInt64 {
        switch sizeKind {
        case .allocated:
            return UInt64(st.st_blocks) &* 512
        case .logical:
            return UInt64(st.st_size)
        }
    }
    
    @inline(__always)
    private func devU64(_ d: dev_t) -> UInt64 {
        return UInt64(bitPattern: Int64(d))
    }

    private func readChildrenFast(at path: String, parentDepth: Int) -> [Metadata] {
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

            let dev = devU64(st.st_dev)       // was: UInt64(st.st_dev)
            if stayOnDevice && dev != rootDev && parentDepth >= 0 {
                continue
            }

            let mode = st.st_mode & S_IFMT
            if mode == S_IFLNK { continue }

            let kind: FileType
            switch mode {
            case S_IFREG: kind = .file
            case S_IFDIR: kind = .directory
            default:      kind = .unknown
            }
            if kind == .unknown { continue }

            let name = String(cString: namePtr)
            let fullPath = path + needsSlash + name

            let size = (kind == .file) ? bytes(for: st) : 0
            results.append(Metadata(
                path: fullPath,
                type: kind,
                sizeIfFile: size,
                dev: dev,
                ino: UInt64(st.st_ino)
            ))
        }
        return results
    }

    @inline(__always)
    private func aggregateDirectoryBytesOpaque(at root: String) -> UInt64 {
        var total: UInt64 = 0
        var stack: [String] = [root]

        while let path = stack.popLast() {
            guard canEnter(path), let dir = opendir(path) else { continue }
            let dfd = dirfd(dir)
            let needsSlash = (path == "/") ? "" : "/"
            defer { closedir(dir) }

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

                if stayOnDevice && devU64(st.st_dev) != rootDev { continue }
                
                let mode = st.st_mode & S_IFMT
                switch mode {
                case S_IFREG:
                    total &+= bytes(for: st)
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
}
