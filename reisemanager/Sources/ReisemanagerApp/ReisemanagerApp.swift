import AppKit
import SwiftUI

/// Start über `swift run ReisemanagerApp`: Ohne App-Bündel muss das Fenster ausdrücklich nach vorn geholt werden.
final class AppStart: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ReisemanagerApp: App {
    @NSApplicationDelegateAdaptor(AppStart.self) private var start
    @StateObject private var modell = AppModell()

    var body: some Scene {
        WindowGroup("Reisemanager") {
            Hauptfenster()
                .environmentObject(modell)
                .frame(minWidth: 980, minHeight: 620)
        }
    }
}
