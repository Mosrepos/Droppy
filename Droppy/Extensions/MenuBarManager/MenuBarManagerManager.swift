//
//  MenuBarManager.swift
//  Droppy
//
//  Menu Bar Manager - Hide/show menu bar icons using divider expansion
//  Uses two NSStatusItems: a visible toggle button and an expanding divider
//

import SwiftUI
import AppKit
import Combine

// MARK: - Menu Bar Manager

@MainActor
final class MenuBarManager: ObservableObject {
    static let shared = MenuBarManager()
    
    // MARK: - Published State
    
    /// Whether the extension is enabled
    @Published private(set) var isEnabled = false
    
    /// Whether hidden icons are currently expanded (visible)
    @Published private(set) var isExpanded = true
    
    /// Whether hover-to-reveal is enabled (on by default)
    @Published var hoverToRevealEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(hoverToRevealEnabled, forKey: hoverToRevealKey)
            if hoverToRevealEnabled {
                startHoverMonitoring()
            } else {
                stopHoverMonitoring()
            }
        }
    }
    
    // MARK: - Status Items
    
    /// The visible toggle button - always shows chevron, click to toggle
    private var toggleItem: NSStatusItem?
    
    /// The invisible divider that expands to push items off-screen
    private var dividerItem: NSStatusItem?
    
    /// Autosave names for position persistence
    private let toggleAutosaveName = "DroppyMenuBarToggle"
    private let dividerAutosaveName = "DroppyMenuBarDivider"
    
    // MARK: - Hover Monitoring
    
    /// Global mouse move monitor for hover detection
    private var mouseMonitor: Any?
    
    /// Whether we are currently in a hover-expanded state (temporary expansion)
    private var isHoverExpanded = false
    
    /// Timer for smooth divider length animation
    private var animationTimer: Timer?
    
    /// Threshold X position - mouse must be to the right of this to trigger hover reveal
    /// This is the right side of the screen where menu bar icons live
    private var hoverThresholdX: CGFloat {
        guard let screen = NSScreen.main else { return 800 }
        // Trigger when mouse is in the right 40% of screen (where menu bar icons typically are)
        return screen.frame.width * 0.6
    }
    
    // MARK: - Constants
    
    /// Standard length for toggle (shows chevron)
    private let toggleLength: CGFloat = NSStatusItem.variableLength
    
    /// Standard length for divider (thin, almost invisible)
    private let dividerStandardLength: CGFloat = 1
    
    /// Expanded length to push items off-screen
    private let dividerExpandedLength: CGFloat = 10_000
    
    // MARK: - Persistence Keys
    
    private let enabledKey = "menuBarManagerEnabled"
    private let expandedKey = "menuBarManagerExpanded"
    private let hoverToRevealKey = "menuBarManagerHoverToReveal"
    
    // MARK: - Initialization
    
    private init() {
        // Only start if extension is not removed
        guard !ExtensionType.menuBarManager.isRemoved else { return }
        
        // Load hover preference (default to true)
        if UserDefaults.standard.object(forKey: hoverToRevealKey) != nil {
            hoverToRevealEnabled = UserDefaults.standard.bool(forKey: hoverToRevealKey)
        } else {
            hoverToRevealEnabled = true
        }
        
        if UserDefaults.standard.bool(forKey: enabledKey) {
            enable()
        }
    }
    
    // MARK: - Public API
    
    /// Enable the menu bar manager
    func enable() {
        guard !isEnabled else { return }
        
        // FIX: Clear any stale removed state when explicitly enabling
        // This fixes the singleton resurrection bug where init guard failed
        // but user later tries to enable via Extensions UI
        if ExtensionType.menuBarManager.isRemoved {
            print("[MenuBarManager] Clearing stale removed state")
            ExtensionType.menuBarManager.setRemoved(false)
        }
        
        isEnabled = true
        UserDefaults.standard.set(true, forKey: enabledKey)
        
        // Create both status items
        createStatusItems()
        
        // Restore previous expansion state, or default to expanded (showing all icons)
        if UserDefaults.standard.object(forKey: expandedKey) != nil {
            isExpanded = UserDefaults.standard.bool(forKey: expandedKey)
        } else {
            isExpanded = true
        }
        applyExpansionState()
        
        // Start hover monitoring if enabled
        if hoverToRevealEnabled {
            startHoverMonitoring()
        }
        
        print("[MenuBarManager] Enabled, expanded: \(isExpanded), hoverToReveal: \(hoverToRevealEnabled)")
    }
    
    /// Disable the menu bar manager
    func disable() {
        guard isEnabled else { return }
        
        isEnabled = false
        UserDefaults.standard.set(false, forKey: enabledKey)
        
        // Stop hover monitoring
        stopHoverMonitoring()
        
        // Show all items before removing
        if !isExpanded {
            isExpanded = true
            applyExpansionState()
        }
        
        // Remove both status items
        removeStatusItems()
        
        print("[MenuBarManager] Disabled")
    }
    
    /// Toggle between expanded and collapsed states
    func toggleExpanded() {
        isExpanded.toggle()
        isHoverExpanded = false // User manually toggled, clear hover state
        UserDefaults.standard.set(isExpanded, forKey: expandedKey)
        applyExpansionState()
        
        // Notify to refresh Droppy menu
        NotificationCenter.default.post(name: .menuBarManagerStateChanged, object: nil)
        
        print("[MenuBarManager] Toggled: \(isExpanded ? "expanded" : "collapsed")")
    }
    
    /// Clean up all resources
    func cleanup() {
        stopHoverMonitoring()
        disable()
        UserDefaults.standard.removeObject(forKey: enabledKey)
        UserDefaults.standard.removeObject(forKey: expandedKey)
        UserDefaults.standard.removeObject(forKey: hoverToRevealKey)
        
        print("[MenuBarManager] Cleanup complete")
    }
    
    // MARK: - Hover Monitoring
    
    private func startHoverMonitoring() {
        guard mouseMonitor == nil, isEnabled else { return }
        
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMove(event)
            }
        }
        
        print("[MenuBarManager] Hover monitoring started")
    }
    
    private func stopHoverMonitoring() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
            print("[MenuBarManager] Hover monitoring stopped")
        }
        
        // Restore to user's saved state if we were hover-expanded
        if isHoverExpanded {
            isHoverExpanded = false
            let savedState = UserDefaults.standard.bool(forKey: expandedKey)
            if isExpanded != savedState {
                isExpanded = savedState
                applyExpansionState()
            }
        }
    }
    
    private func handleMouseMove(_ event: NSEvent) {
        guard isEnabled, hoverToRevealEnabled else { return }
        guard let screen = NSScreen.main else { return }
        
        let mouseLocation = NSEvent.mouseLocation
        
        // Check if mouse is in menu bar area (top 24px of screen)
        let menuBarHeight: CGFloat = 24
        let isInMenuBar = mouseLocation.y >= (screen.frame.maxY - menuBarHeight)
        
        // Check if mouse is in the right portion of the screen (where icons are)
        let isInIconArea = mouseLocation.x >= hoverThresholdX
        
        if isInMenuBar && isInIconArea {
            // Mouse is in the menu bar on the right side - expand if collapsed
            if !isExpanded && !isHoverExpanded {
                isHoverExpanded = true
                isExpanded = true
                applyExpansionState()
                print("[MenuBarManager] Hover expand triggered")
            }
        } else {
            // Mouse left the menu bar area - collapse if we hover-expanded
            if isHoverExpanded && isExpanded {
                isHoverExpanded = false
                let savedState = UserDefaults.standard.bool(forKey: expandedKey)
                isExpanded = savedState
                applyExpansionState()
                print("[MenuBarManager] Hover collapse triggered")
            }
        }
    }
    
    // MARK: - Status Items Creation
    
    private func createStatusItems() {
        // Create the toggle button (always visible, shows chevron)
        toggleItem = NSStatusBar.system.statusItem(withLength: toggleLength)
        toggleItem?.autosaveName = toggleAutosaveName
        
        if let button = toggleItem?.button {
            button.target = self
            button.action = #selector(toggleClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            print("[MenuBarManager] Toggle button configured with click action")
        } else {
            print("[MenuBarManager] ⚠️ WARNING: Toggle button is nil - clicks will not work!")
        }
        
        // Create the divider (expands to hide items)
        // This should be positioned to the LEFT of the toggle
        dividerItem = NSStatusBar.system.statusItem(withLength: dividerStandardLength)
        dividerItem?.autosaveName = dividerAutosaveName
        
        if let button = dividerItem?.button {
            // Make divider nearly invisible - just a thin separator
            button.title = ""
            button.image = nil
            print("[MenuBarManager] Divider configured")
        } else {
            print("[MenuBarManager] ⚠️ WARNING: Divider button is nil - expansion may not work!")
        }
        
        updateToggleIcon()
        
        print("[MenuBarManager] Created status items")
    }
    
    private func removeStatusItems() {
        if let item = toggleItem {
            let autosaveName = item.autosaveName as String
            let cached = StatusItemDefaults.preferredPosition(for: autosaveName)
            NSStatusBar.system.removeStatusItem(item)
            if let pos = cached { StatusItemDefaults.setPreferredPosition(pos, for: autosaveName) }
            toggleItem = nil
        }
        
        if let item = dividerItem {
            let autosaveName = item.autosaveName as String
            let cached = StatusItemDefaults.preferredPosition(for: autosaveName)
            NSStatusBar.system.removeStatusItem(item)
            if let pos = cached { StatusItemDefaults.setPreferredPosition(pos, for: autosaveName) }
            dividerItem = nil
        }
        
        print("[MenuBarManager] Removed status items")
    }
    
    private func updateToggleIcon() {
        guard let button = toggleItem?.button else { return }
        
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        
        if isExpanded {
            // Items visible (expanded) - show chevron pointing right (icons expanded outward)
            // Issue #83: User expects ">" when expanded
            button.image = NSImage(systemSymbolName: "chevron.compact.right", accessibilityDescription: "Hide menu bar icons")?
                .withSymbolConfiguration(config)
        } else {
            // Items hidden (collapsed) - show chevron pointing left (click to expand)
            // Issue #83: User expects "<" when collapsed, indicating "click to expand"
            button.image = NSImage(systemSymbolName: "chevron.compact.left", accessibilityDescription: "Show menu bar icons")?
                .withSymbolConfiguration(config)
        }
    }
    
    private func applyExpansionState(animated: Bool = true) {
        guard let dividerItem = dividerItem else { return }
        
        let targetLength = isExpanded ? dividerStandardLength : dividerExpandedLength
        
        // Cancel any existing animation
        animationTimer?.invalidate()
        animationTimer = nil
        
        if animated {
            animateDividerLength(to: targetLength)
        } else {
            dividerItem.length = targetLength
        }
        
        updateToggleIcon()
    }
    
    /// Animate the divider length with smooth easing
    private func animateDividerLength(to targetLength: CGFloat) {
        guard let dividerItem = dividerItem else { return }
        
        let startLength = dividerItem.length
        let duration: TimeInterval = 0.25 // Snappy but smooth
        let startTime = CACurrentMediaTime()
        let frameInterval: TimeInterval = 1.0 / 60.0 // 60 FPS
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            let elapsed = CACurrentMediaTime() - startTime
            let progress = min(elapsed / duration, 1.0)
            
            // Ease-out cubic for smooth deceleration
            let easedProgress = 1.0 - pow(1.0 - progress, 3)
            
            let currentLength = startLength + (targetLength - startLength) * CGFloat(easedProgress)
            
            Task { @MainActor [weak self] in
                self?.dividerItem?.length = currentLength
            }
            
            if progress >= 1.0 {
                timer.invalidate()
                Task { @MainActor [weak self] in
                    self?.animationTimer = nil
                    // Ensure final value is exact
                    self?.dividerItem?.length = targetLength
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @objc private func toggleClicked() {
        let event = NSApp.currentEvent
        
        if event?.type == .rightMouseUp {
            // Right-click: show menu
            showContextMenu()
        } else {
            // Left-click: toggle expansion
            toggleExpanded()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        let toggleItem = NSMenuItem(
            title: isExpanded ? "Hide Menu Bar Icons" : "Show Menu Bar Icons",
            action: #selector(toggleFromMenu),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.image = NSImage(systemSymbolName: isExpanded ? "eye.slash" : "eye", accessibilityDescription: nil)
        menu.addItem(toggleItem)
        
        menu.addItem(.separator())
        
        // Hover to reveal toggle
        let hoverItem = NSMenuItem(
            title: "Hover to Reveal",
            action: #selector(toggleHoverToReveal),
            keyEquivalent: ""
        )
        hoverItem.target = self
        hoverItem.state = hoverToRevealEnabled ? .on : .off
        hoverItem.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: nil)
        menu.addItem(hoverItem)
        
        menu.addItem(.separator())
        
        let howToItem = NSMenuItem(
            title: "How to Use",
            action: #selector(showHowTo),
            keyEquivalent: ""
        )
        howToItem.target = self
        howToItem.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        menu.addItem(howToItem)
        
        menu.addItem(.separator())
        
        let disableItem = NSMenuItem(
            title: "Disable Menu Bar Manager",
            action: #selector(disableFromMenu),
            keyEquivalent: ""
        )
        disableItem.target = self
        disableItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
        menu.addItem(disableItem)
        
        self.toggleItem?.menu = menu
        self.toggleItem?.button?.performClick(nil)
        self.toggleItem?.menu = nil
    }
    
    @objc private func toggleFromMenu() {
        toggleExpanded()
    }
    
    @objc private func toggleHoverToReveal() {
        hoverToRevealEnabled.toggle()
    }
    
    @objc private func showHowTo() {
        // Show Droppy-style notification
        DroppyAlertController.shared.showSimple(
            style: .info,
            title: "How to Use Menu Bar Manager",
            message: "1. Hold ⌘ (Command) and drag menu bar icons\n2. Move icons to the LEFT of the chevron to hide them\n3. Click the chevron to show/hide those icons\n\nIcons to the right of the chevron stay visible.\n\nTip: Hover over the right side of the menu bar to temporarily reveal hidden icons."
        )
    }
    
    @objc private func disableFromMenu() {
        disable()
    }
    
    // MARK: - Diagnostics
    
    /// Print diagnostic information for troubleshooting
    /// Call this from console or debug menu to diagnose issues
    func printDiagnostics() {
        print("[MenuBarManager] === DIAGNOSTICS ===")
        print("  isRemoved: \(ExtensionType.menuBarManager.isRemoved)")
        print("  isEnabled: \(isEnabled)")
        print("  isExpanded: \(isExpanded)")
        print("  isHoverExpanded: \(isHoverExpanded)")
        print("  hoverToRevealEnabled: \(hoverToRevealEnabled)")
        print("  toggleItem exists: \(toggleItem != nil)")
        print("  toggleItem.button exists: \(toggleItem?.button != nil)")
        print("  toggleItem.button.target set: \(toggleItem?.button?.target != nil)")
        print("  toggleItem.button.action set: \(toggleItem?.button?.action != nil)")
        print("  dividerItem exists: \(dividerItem != nil)")
        print("  dividerItem.length: \(dividerItem?.length ?? -1)")
        print("  mouseMonitor exists: \(mouseMonitor != nil)")
        print("  UserDefaults enabledKey: \(UserDefaults.standard.bool(forKey: enabledKey))")
        print("  UserDefaults expandedKey: \(UserDefaults.standard.object(forKey: expandedKey) ?? "nil")")
        print("  UserDefaults hoverToRevealKey: \(UserDefaults.standard.object(forKey: hoverToRevealKey) ?? "nil (default true)")")
        print("[MenuBarManager] === END DIAGNOSTICS ===")
    }
}

// MARK: - StatusItemDefaults Helper

private enum StatusItemDefaults {
    private static let positionPrefix = "NSStatusItem Preferred Position"
    
    static func preferredPosition(for autosaveName: String) -> Double? {
        UserDefaults.standard.object(forKey: "\(positionPrefix) \(autosaveName)") as? Double
    }
    
    static func setPreferredPosition(_ position: Double, for autosaveName: String) {
        UserDefaults.standard.set(position, forKey: "\(positionPrefix) \(autosaveName)")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openMenuBarManagerSettings = Notification.Name("openMenuBarManagerSettings")
    static let menuBarManagerStateChanged = Notification.Name("menuBarManagerStateChanged")
}

