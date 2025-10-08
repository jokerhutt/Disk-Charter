
public final class AlreadyVisitedList {
    
    private let buckets: [Bucket]
    
    private let mask: Int
    
    init(initialBucketCount: Int = 64) {
        
        let count = max(16, initialBucketCount).getNextPowerOfTwo()
        
        var tmpBucketList: [Bucket] = []
        tmpBucketList.reserveCapacity(count)
        
        for _ in 0..<count {tmpBucketList.append(Bucket())}
        buckets = tmpBucketList
        mask = count - 1
        
    }
    
    @inline(__always)
    private func getBucketIndex(fileId: DevIno) -> Int {
        var hashValue = fileId.dev &* 0x9E3779B185EBCA87 &+ fileId.ino

        hashValue ^= hashValue >> 33
        hashValue &*= 0xff51afd7ed558ccd

        return Int(truncatingIfNeeded: hashValue) & mask
    }
    
    
    @inline(__always)
    func insertIfAbsent(_ key: DevIno) -> Bool {
        
        let index = getBucketIndex(fileId: key)
        let bucket = buckets[index]
        
        bucket.lock.lock()
        
        let inserted = bucket.set.insert(key).inserted
        
        bucket.lock.unlock()
        return inserted
        
    }
    
}

/// Converts the initial bucket count into the nearest power of two
private extension Int {
    func getNextPowerOfTwo() -> Int {
        var v = self - 1
        v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16
        #if arch(arm64) || arch(x86_64)
        v |= v >> 32
        #endif
        return v + 1
    }
}
