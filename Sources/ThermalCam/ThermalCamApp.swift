import AppKit
import SwiftUI

@main
struct ThermalCamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = CameraViewModel()

    var body: some Scene {
        WindowGroup("Thermal Cam") {
            ContentView(model: model)
        }
        .defaultSize(width: 920, height: 720)
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
