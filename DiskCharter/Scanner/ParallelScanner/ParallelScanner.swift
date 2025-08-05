import Foundation
import Darwin
import Atomics


final class ParallelScanner {
    private let taskQueue = BlockingQueue<FileNode>()
    private let taskCount = ManagedAtomic<Int>(0)
    private let childrenLock = NSLock()

    func startWalk(rootPath: String) -> FileNode {
        let rootNode = FileNode(path: rootPath, type: .directory)
        taskCount.store(1, ordering: .relaxed)
        taskQueue.enqueue(rootNode)

        let coreCount = ProcessInfo.processInfo.activeProcessorCount
        let workerCount = max(1, coreCount * 3)

        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)

        for _ in 0..<workerCount {
            group.enter()
            queue.async { [weak self] in
                self?.workerLoop()
                group.leave()
            }
        }

        group.wait()

        return rootNode
    }

    private func workerLoop() {
        while let node = taskQueue.dequeue() {
            scanNode(node)
        }
    }

    private func scanNode(_ node: FileNode) {
        let childrenMetadata = readChildren(at: node.path).filter { $0.type != .symlink }
        let childNodes = childrenMetadata.map { FileNode(path: $0.path, type: $0.type) }

        childrenLock.lock()
        childNodes.forEach { node.addChild($0) }
        childrenLock.unlock()

        let directories = childNodes.filter { $0.type == .directory }
        let files = childNodes.filter { $0.type == .file }

        if !directories.isEmpty {
            taskCount.wrappingIncrement(by: directories.count, ordering: .relaxed)
            directories.forEach { taskQueue.enqueue($0) }
        }

        var fileSizes = Array<UInt64>(repeating: 0, count: files.count)
        if !files.isEmpty {
            DispatchQueue.concurrentPerform(iterations: files.count) { idx in
                fileSizes[idx] = fileSize(at: files[idx].path)
            }
            for (idx, fileNode) in files.enumerated() {
                fileNode.setSize(fileSizes[idx])
            }
        }

        let dirsTotalSize = directories.reduce(0) { $0 + $1.size }
        let filesTotalSize = fileSizes.reduce(0, +)
        let ownSize = node.type == .file ? fileSize(at: node.path) : 0

        node.setSize(dirsTotalSize + filesTotalSize + ownSize)

        taskCount.wrappingDecrement(ordering: .relaxed)
        if taskCount.load(ordering: .relaxed) == 0 {
            taskQueue.close()
        }
    }

    private func fileSize(at path: String) -> UInt64 {
        var st = stat()
        if lstat(path, &st) == 0 {
            return UInt64(st.st_size)
        }
        return 0
    }

    private func readChildren(at path: String) -> [Metadata] {
        var results = [Metadata]()
        guard let dir = opendir(path) else { return results }
        defer { closedir(dir) }

        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX)) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }

            let fullPath = (path as NSString).appendingPathComponent(name)
            var statbuf = stat()
            if lstat(fullPath, &statbuf) == 0 {
                let fileType: FileType
                switch statbuf.st_mode & S_IFMT {
                case S_IFREG: fileType = .file
                case S_IFDIR: fileType = .directory
                case S_IFLNK: fileType = .symlink
                default: fileType = .unknown
                }
                results.append(Metadata(path: fullPath, type: fileType))
            }
        }
        return results
    }
}
