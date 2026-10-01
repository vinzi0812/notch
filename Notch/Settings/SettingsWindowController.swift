import AppKit
import SwiftUI

/// Shows the settings window: toolbar tabs that resize the window to fit each one, as in System
/// Settings and other Mac apps.
///
/// An agent app (no Dock icon, no menu bar) can't count on SwiftUI's `Settings` scene: its
/// `openSettings` action only works from views that live in a SwiftUI scene, and the notch is an
/// `NSHostingView` in our own panel. So the window is built from AppKit pieces hosting SwiftUI:
/// `NSTabViewController` with the toolbar tab style is what the `Settings` scene uses underneath.
final class SettingsWindowController {
    private let settings: NotchSettings
    private var window: NSWindow?

    init(settings: NotchSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }
        // Agent apps aren't active by default; without this the window opens behind the current app.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        // A fixed title rather than the selected tab's name (the macOS default): "Home" in the title
        // bar reads like the notch's Home page, not like settings. The toolbar shows which tab is open.
        tabs.canPropagateSelectedChildViewControllerTitle = false
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: tab.view(settings: settings))
            host.preferredContentSize = tab.size
            let item = NSTabViewItem(viewController: host)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Notch Settings"
        window.toolbarStyle = .preference
        // Kept and reused, so reopening is instant and remembers the selected tab.
        window.isReleasedWhenClosed = false
        window.setContentSize(SettingsTab.allCases[0].size)
        window.center()
        return window
    }
}

/// Resizes the window to the selected tab, keeping its top edge where it is.
private final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let window = view.window, let size = tabViewItem?.viewController?.preferredContentSize else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let newContent = CGRect(x: content.minX, y: content.maxY - size.height, width: size.width, height: size.height)
        window.setFrame(window.frameRect(forContentRect: newContent), display: true, animate: true)
    }
}
