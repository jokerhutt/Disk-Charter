import Foundation

struct FileService {
    
    static func documentsDirectoryPath() -> String {
        let manager = FileManager.default
        
        guard let url = manager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return "No directory found"
        }
        
        return url.path
    }

    static func listDocumentsDirectoryContents() -> Result<[String], Error> {
        let path = documentsDirectoryPath()
        let manager = FileManager.default
        
        do {
            let contents = try manager.contentsOfDirectory(atPath: path)
            return .success(contents)
        } catch {
            return .failure(error)
        }
        
        
        
    }
}
