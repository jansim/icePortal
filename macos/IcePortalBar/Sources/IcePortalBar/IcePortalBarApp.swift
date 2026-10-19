import AppKit
import SwiftUI

@main
struct IcePortalBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TrainStore()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar-only app: no Dock icon, even when run via `swift run`.
        NSApp.setActivationPolicy(.accessory)
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: TrainStore
    @AppStorage(SettingsKey.menuBarDisplay) private var display: MenuBarDisplay = .speed

    var body: some View {
        if let text = store.menuBarText(for: display) {
            HStack(spacing: 4) {
                Image(systemName: "tram.fill")
                Text(text).monospacedDigit()
            }
        } else {
            Image(systemName: store.isConnected ? "tram.fill" : "tram")
        }
    }
}
