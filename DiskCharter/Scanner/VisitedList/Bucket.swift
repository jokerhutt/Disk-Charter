import Foundation
import Darwin
import Atomics

public final class Bucket {
    let lock = NSLock()
    var set = Set<DevIno>()
}
