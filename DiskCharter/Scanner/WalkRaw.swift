
import Darwin
import Foundation

class WalkRaw {
    
    func walkTree (path: String) -> RawFileNode? {
        
        var st = stat()
        
        if lstat(path, &st) != 0 {
            return nil
        }
        
        //Check if Symlink
        if (st.st_mode & S_IFMT) == S_IFLNK {
            return nil
        }
        
        //Check if Dir
        if (st.st_mode & S_IFMT) == S_IFDIR {
            
            guard let dir = opendir(path) else { return nil }
            defer { closedir(dir) }
        
            var children = [RawFileNode]();
            
            while let childEntry = readdir(dir) {
                
                let name = withUnsafePointer(to: &childEntry.pointee.d_name) {
                    $0.withMemoryRebound (
                        to: CChar.self,
                        capacity: Int(NAME_MAX)) {
                            String(cString: $0)
                        }
                }
                
                if name == "." || name == ".." { continue }
                
                let childPath = (path as NSString).appendingPathComponent(name)
                
                if let child = walkTree(path: childPath) {
                    children.append(child)
                    print ("Loading path: \(childPath)")
                }
                
            }
            
            return RawFileNode(
                name: URL(fileURLWithPath: path).lastPathComponent
                ,path: path
                ,size: Int(st.st_size)
                ,children: children
            )
            
        }
        
        return (
            RawFileNode(
                name: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                size: Int(st.st_size),
                children: nil
            )
            
        )

    }
    
    
    
}
