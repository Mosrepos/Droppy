import AppKit
import SwiftUI

/// Manages the settings window for Droppy
final class SettingsWindowController: NSObject, NSWindowDelegate {
    /// Shared instance
    static let shared = SettingsWindowController()
    
    /// The settings window
    private var window: NSWindow?

    var activeSettingsWindow: NSWindow? {
        window
    }
    
    /// Dedicated lightweight window for Menu Bar Manager quick settings
    private var menuBarManagerWindow: NSWindow?
    private var isClosingSettingsWindow = false
    private var isClosingMenuBarManagerWindow = false
    private var settingsDeferredTeardownWorkItem: DispatchWorkItem?
    private var menuBarDeferredTeardownWorkItem: DispatchWorkItem?
    private let deferredTeardownDelay: TimeInterval = 8
    
    private override init() {
        super.init()
    }
    
    /// Shows the settings window, creating it if necessary
    func showSettings() {
        showSettings(openingExtension: nil)
    }
    
    /// Shows the settings window and navigates to a specific tab
    /// - Parameter tab: The settings tab to open
    func showSettings(tab: SettingsTab) {
        pendingTabToOpen = tab
        showSettings(openingExtension: nil)
    }
    
    /// Extension type to open when settings loads (cleared after use)
    private(set) var pendingExtensionToOpen: ExtensionType?
    
    /// Tab to open when settings loads (cleared after use)
    private(set) var pendingTabToOpen: SettingsTab?
    
    /// Shows the settings window with optional extension detail panel
    /// - Parameter extensionType: If provided, will navigate to Extensions and open this extension's detail panel
    func showSettings(openingExtension extensionType: ExtensionType?) {
        // Full settings takes precedence over the lightweight MBM quick window.
        closeMenuBarManagerQuickSettings()

        // Store the pending extension before potentially creating the window
        pendingExtensionToOpen = extensionType
        
        // If window already exists, just bring it to front
        if let window = window {
            cancelSettingsDeferredTeardown()
            NSApp.activate(ignoringOtherApps: true)
            if window.isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                AppKitMotion.prepareForPresent(window, initialScale: 0.9)
                window.orderFront(nil)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                }
                AppKitMotion.animateIn(window, initialScale: 0.9, duration: 0.2)
            }
            
            // Post notification so SettingsView can handle the extension
            if extensionType != nil {
                NotificationCenter.default.post(name: .openExtensionFromDeepLink, object: extensionType)
            }
            return
        }
        
        // Create the SwiftUI view
        let settingsView = SettingsView()

        let hostingView = NSHostingView(rootView: settingsView)
        
        let windowWidth: CGFloat = Self.baseWidth
        let windowHeight: CGFloat = 650
        
        // Create the window
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        newWindow.center()
        newWindow.title = ""
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.standardWindowButton(.closeButton)?.isHidden = true
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newWindow.standardWindowButton(.zoomButton)?.isHidden = true
        
        // Configure background and appearance
        // NOTE: Do NOT use isMovableByWindowBackground to avoid buttons triggering window drag
        newWindow.isMovableByWindowBackground = false
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        newWindow.hasShadow = true
        newWindow.isReleasedWhenClosed = false
        
        newWindow.delegate = self
        newWindow.contentView = hostingView
        
        self.window = newWindow
        AppKitMotion.prepareForPresent(newWindow, initialScale: 0.9)
        
        // Bring to front and activate
        // Use slight delay to ensure NotchWindow's canBecomeKey has time to update
        // after detecting this window is visible
        newWindow.orderFront(nil)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            newWindow.makeKeyAndOrderFront(nil)
            
            // Post notification after window is ready
            if extensionType != nil {
                NotificationCenter.default.post(name: .openExtensionFromDeepLink, object: extensionType)
            }
        }
        AppKitMotion.animateIn(newWindow, initialScale: 0.9, duration: 0.24)
        
        // PREMIUM: Haptic confirms settings opened
        HapticFeedback.expand()
    }
    
    /// Opens a lightweight window that renders only Menu Bar Manager settings.
    /// Used by the menu-bar context menu path for faster startup than full SettingsView.
    func showMenuBarManagerQuickSettings() {
        // If full settings is already open, route to the extension detail panel there.
        if let window {
            cancelSettingsDeferredTeardown()
            NSApp.activate(ignoringOtherApps: true)
            if window.isVisible {
                window.makeKeyAndOrderFront(nil)
            } else {
                AppKitMotion.prepareForPresent(window, initialScale: 0.9)
                window.orderFront(nil)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                }
                AppKitMotion.animateIn(window, initialScale: 0.9, duration: 0.2)
            }
            NotificationCenter.default.post(name: .openExtensionFromDeepLink, object: ExtensionType.menuBarManager)
            return
        }

        if let menuBarManagerWindow {
            cancelMenuBarDeferredTeardown()
            NSApp.activate(ignoringOtherApps: true)
            if menuBarManagerWindow.isVisible {
                menuBarManagerWindow.makeKeyAndOrderFront(nil)
            } else {
                AppKitMotion.prepareForPresent(menuBarManagerWindow, initialScale: 0.95)
                menuBarManagerWindow.orderFront(nil)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    menuBarManagerWindow.makeKeyAndOrderFront(nil)
                }
                AppKitMotion.animateIn(menuBarManagerWindow, initialScale: 0.95, duration: 0.2)
            }
            return
        }

        let content = MenuBarManagerInfoView(
            installCount: nil
        )
        let hostingView = NSHostingView(rootView: content)
        let availableHeight = NSScreen.main?.visibleFrame.height ?? 800
        let windowWidth: CGFloat = 450
        let windowHeight: CGFloat = min(760, max(520, availableHeight - 120))

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        newWindow.center()
        newWindow.title = ""
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.standardWindowButton(.closeButton)?.isHidden = true
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newWindow.standardWindowButton(.zoomButton)?.isHidden = true
        newWindow.isMovableByWindowBackground = false
        newWindow.backgroundColor = .clear
        newWindow.isOpaque = false
        newWindow.hasShadow = true
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.contentView = hostingView

        menuBarManagerWindow = newWindow

        AppKitMotion.prepareForPresent(newWindow, initialScale: 0.95)
        newWindow.orderFront(nil)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            newWindow.makeKeyAndOrderFront(nil)
        }
        AppKitMotion.animateIn(newWindow, initialScale: 0.95, duration: 0.2)
        HapticFeedback.expand()
    }
    
    /// Close the settings window
    func close() {
        closeSettingsWindow()
        closeMenuBarManagerQuickSettings()
    }
    
    /// Close the lightweight Menu Bar Manager quick settings window.
    func closeMenuBarManagerQuickSettings() {
        guard let panel = menuBarManagerWindow, !isClosingMenuBarManagerWindow else { return }
        cancelMenuBarDeferredTeardown()
        isClosingMenuBarManagerWindow = true
        AppKitMotion.animateOut(panel, targetScale: 1.0, duration: 0.15) { [weak self] in
            guard let self else { return }
            panel.orderOut(nil)
            AppKitMotion.resetPresentationState(panel)
            self.isClosingMenuBarManagerWindow = false
            self.scheduleMenuBarDeferredTeardown()
        }
    }

    private func closeSettingsWindow() {
        guard let panel = window, !isClosingSettingsWindow else { return }
        cancelSettingsDeferredTeardown()
        ExtensionDetailWindowController.shared.close()
        isClosingSettingsWindow = true
        AppKitMotion.animateOut(panel, targetScale: 1.0, duration: 0.15) { [weak self] in
            guard let self else { return }
            panel.orderOut(nil)
            AppKitMotion.resetPresentationState(panel)
            self.isClosingSettingsWindow = false
            self.scheduleSettingsDeferredTeardown()
        }
    }

    private func scheduleSettingsDeferredTeardown() {
        settingsDeferredTeardownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.window, !panel.isVisible else { return }
            panel.contentView = nil
            panel.delegate = nil
            self.window = nil
            self.settingsDeferredTeardownWorkItem = nil
        }
        settingsDeferredTeardownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + deferredTeardownDelay, execute: workItem)
    }

    private func scheduleMenuBarDeferredTeardown() {
        menuBarDeferredTeardownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.menuBarManagerWindow, !panel.isVisible else { return }
            panel.contentView = nil
            panel.delegate = nil
            self.menuBarManagerWindow = nil
            self.menuBarDeferredTeardownWorkItem = nil
        }
        menuBarDeferredTeardownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + deferredTeardownDelay, execute: workItem)
    }

    private func cancelSettingsDeferredTeardown() {
        settingsDeferredTeardownWorkItem?.cancel()
        settingsDeferredTeardownWorkItem = nil
    }

    private func cancelMenuBarDeferredTeardown() {
        menuBarDeferredTeardownWorkItem?.cancel()
        menuBarDeferredTeardownWorkItem = nil
    }
    
    /// Clears the pending extension (called after SettingsView consumes it)
    func clearPendingExtension() {
        pendingExtensionToOpen = nil
    }
    
    /// Clears the pending tab (called after SettingsView consumes it)
    func clearPendingTab() {
        pendingTabToOpen = nil
    }

    // MARK: - Window Sizing
    
    /// Base width for regular settings tabs
    static let baseWidth: CGFloat = 920
    
    /// Extended width for extensions tab
    static let extensionsWidth: CGFloat = baseWidth
    
    /// Resize the settings window based on the current tab
    /// - Parameter isExtensions: Whether the extensions tab is selected
    func resizeForTab(isExtensions: Bool) {
        guard let window = window else { return }
        
        let targetWidth = Self.baseWidth
        let currentFrame = window.frame
        
        // Only resize if width actually changed
        guard abs(currentFrame.width - targetWidth) > 1 else { return }
        
        // Calculate new frame, keeping window centered horizontally
        let widthDelta = targetWidth - currentFrame.width
        let newFrame = NSRect(
            x: currentFrame.origin.x - widthDelta / 2,
            y: currentFrame.origin.y,
            width: targetWidth,
            height: currentFrame.height
        )
        
        // Avoid animated frame updates here; they can re-enter layout while SwiftUI
        // is already invalidating constraints during tab/content updates.
        window.setFrame(newFrame, display: true, animate: false)
    }
    
    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === window {
            closeSettingsWindow()
            return false
        }

        if sender === menuBarManagerWindow {
            closeMenuBarManagerQuickSettings()
            return false
        }

        return true
    }
    
    func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow {
            // Aggressively release the hosted SwiftUI tree when the window closes.
            closingWindow.contentView = nil
            closingWindow.delegate = nil
            if closingWindow === window {
                ExtensionDetailWindowController.shared.close()
                window = nil
                isClosingSettingsWindow = false
                cancelSettingsDeferredTeardown()
            }
            if closingWindow === menuBarManagerWindow {
                menuBarManagerWindow = nil
                isClosingMenuBarManagerWindow = false
                cancelMenuBarDeferredTeardown()
            }
        }
    }
}

