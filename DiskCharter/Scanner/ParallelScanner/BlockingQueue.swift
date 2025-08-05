final class BlockingQueue<T> {
    private var queue = [T]()
    private var closed = false
    private let condition = NSCondition()

    func enqueue(_ element: T) {
        condition.lock()
        guard !closed else {
            condition.unlock()
            return
        }
        queue.append(element)
        condition.signal()
        condition.unlock()
    }

    func dequeue() -> T? {
        condition.lock()
        while queue.isEmpty && !closed {
            condition.wait()
        }
        guard !queue.isEmpty else {
            condition.unlock()
            return nil
        }
        let element = queue.removeFirst()
        condition.unlock()
        return element
    }

    func close() {
        condition.lock()
        closed = true
        condition.broadcast()
        condition.unlock()
    }
}
