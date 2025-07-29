
import Foundation
import Combine
import AppKit
import FullDiskAccess

final class FullDiskAccessChecker: ObservableObject {
    
    //Variable for checking if disk granted (refreshes on change)
    @Published var isGranted: Bool = FullDiskAccess.isGranted
    private var cancellables = Set<AnyCancellable>()

    //constructor
    init() {
        // Subscribe to system notif when back in view
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refreshFullDiskAccessStatus()
            }
            .store(in: &cancellables)
    }

    //Check refreshStatus
    func refreshFullDiskAccessStatus() {
        isGranted = FullDiskAccess.isGranted
    }

    
    func openSettingsPrompt() {    
        guard !isGranted else { return }

        FullDiskAccess.promptIfNotGranted(
            title: "Enable Full Disk Access for CleanDifferent",
            message: "CleanDifferent requires Full Disk Access to read your files.",
            settingsButtonTitle: "Open Settings",
            skipButtonTitle: "Later",
            canBeSuppressed: false,
            icon: nil
        )
    }

    func canAccessHomeDirectory() -> Bool {
        return isGranted
    }

    func readHomeDirectory() -> Result<[String], Error> {
        let fm = FileManager.default
        let path = fm.homeDirectoryForCurrentUser.path

        do {
            let files = try fm.contentsOfDirectory(atPath: path)
            return .success(files)
        } catch {
            return .failure(error)
        }
    }
}

