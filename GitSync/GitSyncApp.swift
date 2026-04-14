import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(manager: GitSyncManager.shared)
    }
}

@main
struct GitSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var manager = GitSyncManager.shared

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
