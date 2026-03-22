import SwiftUI
import AppKit

@main
struct BarClawApp: App {
    @StateObject private var service = OpenClawService()

    var body: some Scene {
        MenuBarExtra {
            AppPanel()
                .environmentObject(service)
                .frame(width: 460, height: 560)
        } label: {
            MenuBarIcon(isOnline: service.isOnline)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Menu bar icon — lobster emoji with a tiny live status dot.
/// Right-click shows Relaunch / Quit options.
struct MenuBarIcon: View {
    let isOnline: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text("🦞")
                .font(.system(size: 15))
            Circle()
                .fill(isOnline ? Color.green : Color(NSColor.tertiaryLabelColor))
                .frame(width: 5, height: 5)
                .offset(x: 1, y: 1)
            // Invisible overlay captures right-clicks
            RightClickReceiver()
        }
        .help("BarClaw — right-click for options")
    }
}

// MARK: - Right-click context menu

/// Transparent NSView that intercepts right-clicks and shows a context menu.
private struct RightClickReceiver: NSViewRepresentable {
    func makeNSView(context: Context) -> RightClickView { RightClickView() }
    func updateNSView(_ nsView: RightClickView, context: Context) {}
}

final class RightClickView: NSView {
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()

        let relaunch = NSMenuItem(title: "Relaunch BarClaw", action: #selector(relaunchApp), keyEquivalent: "")
        relaunch.target = self
        menu.addItem(relaunch)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit BarClaw", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = .command
        menu.addItem(quit)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func relaunchApp() {
        guard let url = Bundle.main.bundleURL as URL? else {
            NSApp.terminate(nil)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in }
        NSApp.terminate(nil)
    }
}
