//
//  Scanner.swift
//  CleanDiff
//
//  Created by David Glogowski on 29/07/2025.
//



import Foundation

struct Scanner {
    
    let startingPath: URL
    var currentPath: URL
    
    var searchedPath: [FileNode]
    
    let MAX_DEPTH: Int = 2

    init() {
        self.startingPath = ScannerUtils.getCurrentDirectoryUrl()
        self.currentPath = startingPath
        self.searchedPath = []
    }
    
    public static func scanDirectory (start: URL, curr: URL, depth: Int, maxDepth: Int) -> FileNode {
    
        print ("Curr: \(curr)" )
        let isADirectory = ScannerUtils.checkIfDirectory(curr)
        
        if isADirectory && depth < maxDepth {
            
            let children = ScannerUtils.getChildren(of: curr)
            var childNodes = [] as [FileNode]
            
            for child in children {
                let childNode = scanDirectory(start: start, curr: child, depth: depth + 1, maxDepth: maxDepth)
                childNodes.append(childNode)
            }
            let currentNode = FileNode(url: curr, isDirectory: true, depth: depth, children: childNodes)
            return currentNode
        } else {
            let currentNode = FileNode(url: curr, isDirectory: false, depth: depth, children: nil)
            return currentNode
        }
        
    }
    
    
    
    
    
    
    
    
    
    
    
}
