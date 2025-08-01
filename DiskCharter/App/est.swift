import Foundation

let fs = FileManager.default

func checkIsDirectory (nodePath: String) -> Bool {
    
    var isDir: ObjCBool = false
    
    if !fs.fileExists(atPath: nodePath, isDirectory: &isDir) {
        
        return false
        
    }
    
    return isDir.boolValue
    
}

func scanRawTree(at path: String) -> String {
    
    do{
        
        let start = Date.timeIntervalSinceReferenceDate
        
        var folders: Set<String> = .init([path])
        
        var searchedFolders: Set<String> = .init()
        
        var foundFiles: Set<String> = .init()
        
        repeat {
            
            let folder = folders.removeFirst()
            
            do {
                
                let contents = try fs.contentsOfDirectory(atPath: folder)
                
                for content in contents {
                    
                    let nodePath = folder + "/" + content
                    
                    print("Scanning path: \(nodePath)")
                    
                    let attrs = try? fs.attributesOfItem(atPath: nodePath)
                    
                    if let type = attrs?[.type] as? FileAttributeType, type == .typeSymbolicLink {
                        
                        print("Skipping symlink: \(nodePath)")
                        
                        continue
                        
                    }
                    
                    if checkIsDirectory(nodePath: nodePath) {
                        
                        folders.insert(nodePath)
                        
                    } else {
                        
                        foundFiles.insert(nodePath)
                        
                    }
                    
                }
                
                searchedFolders.insert(folder)
                
            } catch {
                
                print("Failed to read folder: \(folder) and \(error.localizedDescription)")
                
            }
            
        } while !folders.isEmpty
        
        let end = Date.timeIntervalSinceReferenceDate
        
        let duration = end - start
        
        return "Scanned in \(duration.rounded()) seconds"
        
    }
    
}
