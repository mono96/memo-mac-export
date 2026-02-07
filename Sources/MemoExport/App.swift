import SwiftUI
import AppKit

// Shared NotesService instance so AppDelegate can access it for cleanup
let sharedNotesService = NotesService()

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Kill all running osascript processes to release Notes.app
        Task {
            await sharedNotesService.terminateAll()
        }
        // Also kill any stray osascript processes spawned by this app
        killStrayOsascriptProcesses()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /// Find and kill osascript processes that are children of this process
    private func killStrayOsascriptProcesses() {
        let myPid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-P", "\(myPid)", "osascript"]
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        for line in output.split(separator: "\n") {
            if let pid = Int32(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                kill(pid, SIGTERM)
            }
        }
    }
}

@main
struct MemoExportApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 420, height: 380)
        // TODO: 上級者向けメニュー（開発中）
        // .commands {
        //     CommandMenu("上級者向け") { ... }
        // }
    }
}
