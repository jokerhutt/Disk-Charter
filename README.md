## Disk Charter for MacOS
This project aims to scan a MacOS disk as quickly as possible and provide visual and interactive sunburst & tree diagrams.

## Technologies Used
- Swift
- SwiftUI
- AppKit

## Packages Required
- FullDiskAccess package: https://github.com/inket/FullDiskAccess
- swift-atomics: https://github.com/apple/swift-atomics
- SwiftSunburstDiagram package: https://github.com/jokerhutt/SwiftSunburstDiagram
  - Note: you MUST use my forked version, as the original uses UI Kit and does not work on MacOS. 

## Scanner(s)
Currently there are two scanners.
- The parallel scanner scans the disk by throwing folders into a task queue and having multiple threads work on them at once. Keeps adding new folders to the queue until everything is done.
  - Time to scan my entire file system: ~58 seconds
- The batch scanner scans the disk in big batches of folders at a time to reduce locking and speed things up. Builds a map of all files and folders first, then connects them into a tree later.
  - Time to scan my entire file system: ~96 seconds
