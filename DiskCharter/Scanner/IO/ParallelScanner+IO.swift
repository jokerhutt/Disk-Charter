import Foundation
import Darwin
import Atomics

extension ParallelScanner {
    
    enum SizeKind { case allocated, logical }
    
    @inline(__always)
    func devU64(_ d: dev_t) -> UInt64 {
        return UInt64(bitPattern: Int64(d))
    }
    
    func readChildrenFast(at path: String, parentDepth: Int) -> [Metadata] {
        var results: [Metadata] = []

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

            let dev = devU64(st.st_dev)
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
    private func bytes(for st: stat) -> UInt64 {
        switch sizeKind {
        case .allocated:
            return UInt64(st.st_blocks) &* 512
        case .logical:
            return UInt64(st.st_size)
        }
    }
    
    @inline(__always)
    private func canEnter(_ path: String) -> Bool {
        access(path, X_OK) == 0
    }
    

    
    
}
