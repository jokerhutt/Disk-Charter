
import Darwin
import Foundation


class BatchScanner {
    private let queue = DispatchQueue.global(qos: .userInteractive)
    private let group = DispatchGroup()

    private let batchSize = 512

    private var nodes = [String: (name: String, size: Int, children: [String])]()
    private var visitedInodes = Set<UInt64>()
    private var visitedLock = os_unfair_lock_s()
    private var nodesLock = os_unfair_lock_s()

    func start(path: String) async -> RawFileNode? {
        group.enter()

        queue.async {
            self.walkTree(paths: [path])
            self.group.leave()
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.group.wait()
                continuation.resume()
            }
        }

        return buildTree(rootPath: path)
    }

    private func walkTree(paths: [String]) {
        var nextBatch = [String]()

        for path in paths {
            var st = stat()
            if lstat(path, &st) != 0 { continue }

            let uniqueID = UInt64(st.st_dev) << 32 | UInt64(st.st_ino)
            os_unfair_lock_lock(&visitedLock)
            let isNew = visitedInodes.insert(uniqueID).inserted
            os_unfair_lock_unlock(&visitedLock)

            if !isNew { continue }

            if (st.st_mode & S_IFMT) == S_IFLNK { continue }

            if (st.st_mode & S_IFMT) == S_IFDIR {
                guard let dir = opendir(path) else { continue }
                defer { closedir(dir) }

                var childPaths = [String]()

                while let childEntry = readdir(dir) {
                    let name = withUnsafePointer(to: &childEntry.pointee.d_name) {
                        $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX)) {
                            String(cString: $0)
                        }
                    }

                    if name == "." || name == ".." { continue }
                    let childPath = (path as NSString).appendingPathComponent(name)
                    childPaths.append(childPath)
                }

                os_unfair_lock_lock(&nodesLock)
                nodes[path] = (
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    size: Int(st.st_size),
                    children: childPaths
                )
                os_unfair_lock_unlock(&nodesLock)

                nextBatch.append(contentsOf: childPaths)
            } else {
                os_unfair_lock_lock(&nodesLock)
                nodes[path] = (
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    size: Int(st.st_size),
                    children: []
                )
                os_unfair_lock_unlock(&nodesLock)
            }
        }

        let batches = nextBatch.chunked(into: batchSize)
        for batch in batches {
            group.enter()
            queue.async {
                self.walkTree(paths: batch)
                self.group.leave()
            }
        }
    }

    private func buildTree(rootPath: String) -> RawFileNode? {
        guard let nodeInfo = nodes[rootPath] else { return nil }
        let childNodes = nodeInfo.children.compactMap { buildTree(rootPath: $0) }
        let totalSize = childNodes.reduce(nodeInfo.size) { $0 + $1.size }
        return RawFileNode(
            name: nodeInfo.name,
            path: rootPath,
            size: totalSize,
            children: childNodes.isEmpty ? nil : childNodes
        )
    }
    
}




extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
