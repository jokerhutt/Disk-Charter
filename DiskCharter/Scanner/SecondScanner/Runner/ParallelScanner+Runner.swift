import Foundation
import Darwin
import Atomics

extension ParallelScanner {
    
    func run(_ rootPath: String) -> FileNode {
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
    
    
}
