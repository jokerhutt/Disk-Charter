import Foundation


final class BlockingQueue<T> {
    private var storage: [T?]
    private var head = 0, tail = 0, count = 0
    private var closed = false
    private let queueLock = NSCondition()

    init(initialCapacity: Int = 4096) {
        let cap = max(16, initialCapacity.getNextPowerOfTwo())
        storage = Array(repeating: nil, count: cap)
    }

    func enqueue(_ element: T) {
        queueLock.lock()
        guard !closed else { queueLock.unlock(); return }
        if count == storage.count { grow() }
        storage[tail] = element
        tail = (tail &+ 1) & (storage.count - 1)
        count &+= 1
        queueLock.signal()
        queueLock.unlock()
    }

    func enqueueMany(_ items: [T]) {
        queueLock.lock()
        guard !closed else { queueLock.unlock(); return }
        if count + items.count > storage.count { grow(toFit: count + items.count) }
        for e in items {
            storage[tail] = e
            tail = (tail &+ 1) & (storage.count - 1)
            count &+= 1
        }
        queueLock.broadcast()
        queueLock.unlock()
    }

    func dequeue() -> T? {
        queueLock.lock()
        while count == 0 && !closed { queueLock.wait() }
        guard count > 0 else { queueLock.unlock(); return nil }
        let e = storage[head]
        storage[head] = nil
        head = (head &+ 1) & (storage.count - 1)
        count &-= 1
        queueLock.unlock()
        return e!
    }

    func close() { queueLock.lock(); closed = true; queueLock.broadcast(); queueLock.unlock() }

    private func grow() { grow(toFit: storage.count << 1) }
    private func grow(toFit need: Int) {
        let old = storage
        var newCap = old.count
        while newCap < need { newCap <<= 1 }
        var newStore = Array<T?>(repeating: nil, count: newCap)
        for i in 0..<count {
            let idx = (head &+ i) & (old.count - 1)
            newStore[i] = old[idx]
        }
        storage = newStore
        head = 0; tail = count
    }
}
private extension Int {
    func getNextPowerOfTwo() -> Int {
        var v = self - 1
        v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16
        #if arch(x86_64) || arch(arm64)
        v |= v >> 32
        #endif
        return v + 1
    }
}
