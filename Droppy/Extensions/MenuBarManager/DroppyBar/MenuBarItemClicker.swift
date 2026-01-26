//
//  MenuBarItemClicker.swift
//  Droppy
//
//  Handles clicking menu bar items by temporarily showing them.
//  Based on Ice's tempShowItem mechanism.
//

import Cocoa

/// Handles clicking hidden menu bar items by temporarily moving them to visible area
@MainActor
final class MenuBarItemClicker {
    
    /// Shared instance
    static let shared = MenuBarItemClicker()
    
    /// Context for a temporarily shown item
    private struct TempShownItemContext {
        let info: MenuBarItemInfo
        let originalFrame: CGRect
    }
    
    /// Currently temp-shown items waiting to be returned
    private var tempShownContexts: [TempShownItemContext] = []
    
    /// Timer to return items to their original position
    private var returnTimer: Timer?
    
    /// Default interval before returning items (seconds)
    private let returnInterval: TimeInterval = 5.0
    
    private init() {}
    
    // MARK: - Public API
    
    /// Click a menu bar item by temporarily showing it
    /// - Parameters:
    ///   - item: The menu bar item to click
    ///   - mouseButton: Which mouse button to use (.left or .right)
    func clickItem(_ item: MenuBarItem, mouseButton: CGMouseButton = .left) {
        Task { @MainActor in
            // If item is already visible, just click it directly
            if item.isOnScreen, let currentFrame = MenuBarItem.getCurrentFrame(for: item.windowID) {
                await performClick(at: currentFrame, mouseButton: mouseButton, ownerPID: item.ownerPID)
                return
            }
            
            // Item is hidden - we need to show it first
            await tempShowAndClick(item: item, mouseButton: mouseButton)
        }
    }
    
    // MARK: - Private Implementation
    
    /// Temporarily show an item, click it, then schedule return
    private func tempShowAndClick(item: MenuBarItem, mouseButton: CGMouseButton) async {
        // First, expand the menu bar to show hidden items
        MenuBarManager.shared.setExpanded(true)
        
        // Wait for expansion
        try? await Task.sleep(for: .milliseconds(150))
        
        // Try to get the item's current (now visible) frame
        guard let currentFrame = MenuBarItem.getCurrentFrame(for: item.windowID),
              currentFrame.width > 0 else {
            print("[Clicker] Could not get visible frame for \(item.displayName)")
            // Fallback: just activate the app
            if let app = item.owningApplication {
                app.activate()
            }
            return
        }
        
        // Click the item
        await performClick(at: currentFrame, mouseButton: mouseButton, ownerPID: item.ownerPID)
        
        // Store context for returning later
        let context = TempShownItemContext(info: item.info, originalFrame: item.frame)
        tempShownContexts.append(context)
        
        // Schedule return (collapse menu bar after delay)
        scheduleReturn()
        
        print("[Clicker] Clicked \(item.displayName)")
    }
    
    /// Perform a click at the given frame
    private func performClick(at frame: CGRect, mouseButton: CGMouseButton, ownerPID: pid_t) async {
        let clickPoint = CGPoint(x: frame.midX, y: frame.midY)
        
        // Create mouse events
        let mouseDownType: CGEventType = mouseButton == .left ? .leftMouseDown : .rightMouseDown
        let mouseUpType: CGEventType = mouseButton == .left ? .leftMouseUp : .rightMouseUp
        
        // Create a proper event source
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            print("[Clicker] Could not create event source")
            return
        }
        
        // Create mouse down event
        guard let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: mouseDownType,
            mouseCursorPosition: clickPoint,
            mouseButton: mouseButton
        ) else {
            print("[Clicker] Could not create mouseDown event")
            return
        }
        
        // Create mouse up event
        guard let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: mouseUpType,
            mouseCursorPosition: clickPoint,
            mouseButton: mouseButton
        ) else {
            print("[Clicker] Could not create mouseUp event")
            return
        }
        
        // Set target PID for the events
        mouseDown.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(ownerPID))
        mouseUp.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(ownerPID))
        
        // Set window ID fields
        // Note: We'd need the window ID here for full accuracy, but PID targeting usually works
        
        // Post events
        mouseDown.post(tap: .cghidEventTap)
        
        try? await Task.sleep(for: .milliseconds(50))
        
        mouseUp.post(tap: .cghidEventTap)
        
        print("[Clicker] Posted click at (\(clickPoint.x), \(clickPoint.y))")
    }
    
    /// Schedule collapsing the menu bar after a delay
    private func scheduleReturn() {
        returnTimer?.invalidate()
        
        returnTimer = Timer.scheduledTimer(withTimeInterval: returnInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.returnTempShownItems()
            }
        }
    }
    
    /// Return all temp-shown items (collapse menu bar)
    private func returnTempShownItems() {
        guard !tempShownContexts.isEmpty else { return }
        
        print("[Clicker] Returning \(tempShownContexts.count) temp-shown items")
        
        // Clear contexts
        tempShownContexts.removeAll()
        
        // Collapse the menu bar
        // Only if user hasn't manually expanded it
        let savedState = UserDefaults.standard.bool(forKey: "menuBarManagerExpanded")
        if !savedState {
            MenuBarManager.shared.setExpanded(false)
        }
        
        returnTimer = nil
    }
}
