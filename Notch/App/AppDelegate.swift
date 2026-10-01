//
//  AppDelegate.swift
//  Notch
//
//  Created by Vineet Parmar on 25/09/26.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    
    private var panel: NotchPanel?
    private var viewModel: NotchViewModel?
    private let settings: NotchSettings
    private let mediaKeys = MediaKeyTap()
    private var accessibilityWait: Task<Void, Never>?
    /// The frontmost app's menus run into the ears' space, so the collapsed notch goes without them.
    private var menusReachEars = false
    private var menusWouldReach = false
    private var frontmostIsFullScreen = false
    private var menuBarPresence = MenuBarPresence()
    private var menuCheck: Task<Void, Never>?
    private lazy var settingsWindow = SettingsWindowController(settings: settings)
    private var monitors: [Any] = []
    private var screenChangeTask: Task<Void, Never>?
    private var menuTrackingTasks: [Task<Void, Never>] = []
    private var dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
    private let notifications = NotificationService()

    override init() {
        // Before the settings load, so they load what the sandboxed version saved.
        SandboxMigration.runIfNeeded()
        settings = NotchSettings()
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        
        guard let geometry = currentGeometry() else { return }
        
        let viewModel = NotchViewModel(geometry: geometry, settings: settings, notes: NotesStore())
        self.viewModel = viewModel
        let panel = NotchPanel(contentRect: geometry.panelRect)
        panel.contentView = NSHostingView(rootView: NotchView(viewModel: viewModel))
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        
        viewModel.onExpandedChange = { [weak self, weak panel, weak viewModel] expanded in
            panel?.ignoresMouseEvents = !expanded
            if expanded {
                viewModel?.launchAtLogin.refresh()
            } else {
                self?.checkMenuBar()   // the app's menus may have changed while it was open
            }
        }
        
        self.panel = panel
        
        let timer = viewModel.timer
        timer.onStart = { [notifications, settings] in
            guard settings.timerNotifies else { return }
            Task { await notifications.requestAuthorizationIfNeeded() }
        }
        timer.onFinish = { [notifications, settings, weak timer, weak viewModel] in
            guard let timer else { return }
            if settings.timerNotifies {
                notifications.postTimerFinished(duration: timer.state.duration, playsSound: settings.timerPlaysSound)
            }
            viewModel?.showActivity(from: timer)
        }

        viewModel.battery.onPluggedIn = { [weak viewModel] in
            guard let viewModel else { return }
            viewModel.showActivity(from: viewModel.battery)
        }

        viewModel.onOpenSettings = { [weak self] in
            self?.settingsWindow.show()
        }
        // Clicking into another app ends typing in the notch, even if SwiftUI still thinks the
        // editor is focused; otherwise the notch would stay open.
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak viewModel] _ in
            MainActor.assumeIsolated { viewModel?.setEditingText(false) }
        }

        viewModel.bluetooth.onConnected = { [weak viewModel] _ in
            guard let viewModel else { return }
            // Longer than other pop-ups: the batteries arrive a moment after the connection.
            viewModel.showActivity(from: viewModel.bluetooth, for: .seconds(4))
        }
        viewModel.levels.onShow = { [weak viewModel] in
            viewModel?.showLevels()
        }
        mediaKeys.onKey = { [weak viewModel] key, fine in
            viewModel?.levels.handle(key, fine: fine) ?? false
        }

        watchMenuBar()

        settings.onGeometryChanged = { [weak self] in
            self?.updateGeometry()
        }
        settings.onFeaturesChanged = { [weak self] in
            self?.applyFeatureSettings()
        }
        applyFeatureSettings()
        viewModel.nowPlaying.onTrackChanged = { [weak viewModel] _ in
            guard let viewModel else { return }
            viewModel.showActivity(from: viewModel.nowPlaying)
        }

        viewModel.calendar.onEventStarted = { [weak viewModel] _ in
            guard let viewModel else { return }
            viewModel.showActivity(from: viewModel.calendar)
        }
        
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown], handler: { [weak self] event in
            self?.handleMouseEvent(event)
        }) {
            monitors.append(global)
        }
        
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown], handler: { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }) {
            monitors.append(local)
        }
        
        // While one of our menus is open the pointer is over the menu, not the notch;
        // hold the notch open until the menu closes, then re-check where the pointer is.
        menuTrackingTasks = [
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: NSMenu.didBeginTrackingNotification) {
                    self?.viewModel?.holdOpen()
                }
            },
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: NSMenu.didEndTrackingNotification) {
                    self?.viewModel?.releaseHold()
                    self?.handleMouseMoved()
                }
            },
        ]

        screenChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification
            ) {
                self?.updateGeometry()
            }
        }
        
    }
    
    /// Starts or stops the parts of hidden features that do work in the background.
    private func applyFeatureSettings() {
        guard let viewModel else { return }
        if settings.isVisible(.nowPlaying) {
            viewModel.nowPlaying.start()   // no-op when already running
        } else {
            viewModel.nowPlaying.stop()    // ends the helper process
        }
        if settings.isVisible(.devices) {
            viewModel.bluetooth.start()    // macOS asks for Bluetooth permission the first time
        } else {
            viewModel.bluetooth.stop()
        }
        if settings.isVisible(.levels) {
            startMediaKeys()
        } else {
            accessibilityWait?.cancel()
            mediaKeys.stop()               // the keys go back to macOS
        }
    }

    /// Takes over the volume and brightness keys, asking for Accessibility permission first if needed
    /// and starting as soon as it's granted (no relaunch).
    private func startMediaKeys() {
        guard !mediaKeys.isRunning else { return }
        if MediaKeyTap.isTrusted {
            mediaKeys.start()
            return
        }
        MediaKeyTap.requestTrust()
        accessibilityWait?.cancel()
        accessibilityWait = Task { [weak self] in
            while !Task.isCancelled, !MediaKeyTap.isTrusted {
                try? await Task.sleep(for: .seconds(2))
            }
            guard !Task.isCancelled else { return }
            self?.mediaKeys.start()
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            handleMouseMoved(isDraggingFile: isDraggingFile())
        default:
            handleMouseMoved()
        }
    }

    /// True while the current drag carries files: the drag pasteboard was written since the mouse
    /// went down and holds file URLs or file promises (e.g. a screenshot thumbnail).
    /// Window drags and text selection don't qualify.
    private func isDraggingFile() -> Bool {
        // With no module taking files (the Files feature hidden), a file drag is just a drag.
        guard viewModel?.modules.contains(where: \.acceptsFileDrops) == true else { return false }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragPasteboardChangeCount, let types = pasteboard.types else { return false }
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        return types.contains(.fileURL) || types.contains(where: promiseTypes.contains)
    }

    private func handleMouseMoved(isDraggingFile: Bool = false) {
        guard let viewModel else { return }
        followMenuBar()
        
        let mouse = NSEvent.mouseLocation
        let geometry = viewModel.geometry
        let height = viewModel.hoverHeight { geometry.hoverTarget(isExpanded: true, height: $0, isDraggingFile: false).contains(mouse) }
        let activeRect = geometry.hoverTarget(isExpanded: viewModel.isExpanded, height: height, isDraggingFile: isDraggingFile)
        
        if activeRect.contains(mouse) {
            viewModel.pointerEntered(isDraggingFile: isDraggingFile)
            if isDraggingFile {
                viewModel.showDropTarget()
            }
        } else {
            viewModel.pointerLeft()
        }
        
    }
    
    /// The notch on the current screen, shaped by the user's Look settings.
    private func currentGeometry() -> NotchGeometry? {
        let notchedScreen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        guard let screen = notchedScreen ?? NSScreen.main else { return nil }
        var geometry = NotchGeometry(screen: screen)
        geometry.expandedWidth = settings.width.points
        geometry.showsEars = settings.showsEars && !menusReachEars
        geometry.extraPageHeight = settings.calendarLayout == .above ? NotchGeometry.calendarMonthAboveExtra : 0
        return geometry
    }
    
    /// Watches for app switches (each app has its own menus) and space switches (entering or
    /// leaving full screen changes space).
    private func watchMenuBar() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkMenuBar() }
            }
        }
        checkMenuBar()
    }

    /// Hides the ears while the frontmost app's menus reach into their space and the menu bar is
    /// showing. Whether the menus reach is read on app and space switches (after a moment: a newly
    /// active app's menu bar takes a beat to settle). In full screen the menu bar comes and goes with
    /// the pointer, so the pointer's moves decide (`followMenuBar`); nothing polls.
    private func checkMenuBar() {
        menuCheck?.cancel()
        menuCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, let viewModel = self.viewModel,
                  viewModel.geometry.kind == .hardware else { return }
            let geometry = viewModel.geometry
            self.menusWouldReach = MenuBarClearance.frontmostMenuTitles().map {
                !MenuBarClearance.earsFit(menuTitles: $0, notch: geometry.notchRect, earWidth: NotchGeometry.earWidth)
            } ?? false   // unreadable without Accessibility: keep the ears
            self.frontmostIsFullScreen = self.menusWouldReach && MenuBarClearance.frontmostIsFullScreen()
            self.menuBarPresence.reset()
            self.followMenuBar()
        }
    }

    /// Re-decides the ears from the pointer: cheap, so it runs on every mouse move.
    private func followMenuBar() {
        guard menusWouldReach else { return setMenusReachEars(false) }
        guard frontmostIsFullScreen, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else {
            return setMenusReachEars(true)   // a menu bar that's always showing
        }
        let pointerY = NSEvent.mouseLocation.y
        let top = screen.frame.maxY
        let menuBarHeight = top - screen.visibleFrame.maxY
        // A menu can only be open while the menu bar is revealed, so look for one only then.
        let menuOpen = menuBarPresence.isRevealed && pointerY < top - menuBarHeight && MenuBarClearance.frontmostHasMenuOpen()
        let showing = menuBarPresence.update(pointerY: pointerY, screenTop: top, menuBarHeight: menuBarHeight, menuOpen: menuOpen)
        setMenusReachEars(showing)
    }

    private func setMenusReachEars(_ reach: Bool) {
        guard reach != menusReachEars else { return }
        menusReachEars = reach
        withAnimation(NotchMotion.earHandover(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)) {
            updateGeometry()
        }
    }

    /// Rebuilds the geometry after the screen or a Look setting changed, and moves the panel to match.
    private func updateGeometry() {
        guard let panel, let viewModel, let geometry = currentGeometry() else { return }
        viewModel.geometry = geometry
        panel.setFrame(geometry.panelRect, display: true)
    }
    
}
