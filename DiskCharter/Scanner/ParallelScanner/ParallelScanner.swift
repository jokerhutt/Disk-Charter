import Foundation
import Darwin
import Atomics


final class ParallelScanner {
    
    let taskQueue = BlockingQueue<FileNode>()
    let dirTaskCount = ManagedAtomic<Int>(0)

    private let includeFiles: Bool
    private let maxDepth: Int
    private let workerCountHint: Int
    
    
    // == I/O == //
    let sizeKind: SizeKind
    let stayOnDevice: Bool
    var rootDev: UInt64 = 0
    
    private let visited = AlreadyVisitedList(initialBucketCount: 128)

    init(
        includeFiles: Bool = false,
        maxDepth: Int = .max,
        workerCountHint: Int? = nil,
        sizeKind: SizeKind = .allocated,
        stayOnDevice: Bool = true
    ) {
        self.includeFiles = includeFiles
        self.maxDepth = maxDepth
        self.sizeKind = sizeKind
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
            completeDirectoryTask(dirNode);
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
                if visited.insertIfAbsent(key) {
                    immediateFileBytes &+= m.sizeIfFile
                }
                if includeFiles {
                    let child = FileNode(path: m.path, type: .file, parent: dirNode, depth: dirNode.depth + 1)
                    child.storeImmediateSize(m.sizeIfFile)
                    dirNode.addChild(child)
                }

            case .directory:
                if !visited.insertIfAbsent(key) { continue }

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

        completeDirectoryTask(dirNode);
    }
    
}
