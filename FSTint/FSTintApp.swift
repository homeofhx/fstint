import AppKit
import SwiftUI

@main
struct FSTintApp: App {
    @NSApplicationDelegateAdaptor(FSTintAppDelegate.self) private var appDelegate
    @StateObject private var tintController = TintController.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(tintController)
        } label: {
            Label("FSTint", systemImage: tintController.menuBarSymbol)
        }.menuBarExtraStyle(.window)
    }
}

final class FSTintAppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        TintController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        TintController.shared.stop()
    }

}
