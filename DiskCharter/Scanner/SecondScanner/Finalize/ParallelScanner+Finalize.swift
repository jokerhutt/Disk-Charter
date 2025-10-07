
extension ParallelScanner {
    
    func completeDirectoryTask(_ node: FileNode) {
        attemptFinalizeAndBubble(node);
        maybeCloseQueueAfterDirDone();
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
    
    private func onChildDirectoryFinished(parent: FileNode, childBytes: UInt64) {
        parent.addToAggregate(childBytes)
        if parent.decrementPendingDirAndLoad() == 0 {
            if let total = parent.finalizeIfNeeded(), let pp = parent.parent {
                onChildDirectoryFinished(parent: pp, childBytes: total)
            }
        }
    }
    
    
    
    
}
