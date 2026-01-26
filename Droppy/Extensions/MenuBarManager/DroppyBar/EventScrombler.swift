//
//  EventScrombler.swift
//  Droppy
//
//  Ice-style event delivery for reliably clicking menu bar items.
//  Uses dual EventTap pattern to route events to background apps.
//

import Cocoa
import Carbon.HIToolbox

/// Error types for event delivery
enum EventError: Error, LocalizedError {
    case invalidEventSource
    case eventCreationFailure
    case eventTapCreationFailed
    case eventTapTimeout
    case eventDeliveryFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidEventSource: return "Could not create event source"
        case .eventCreationFailure: return "Could not create CGEvent"
        case .eventTapCreationFailed: return "Could not create event tap"
        case .eventTapTimeout: return "Event tap timed out"
        case .eventDeliveryFailed: return "Event delivery failed"
        }
    }
}

/// Ice-style event delivery using scromble mechanism
@MainActor
final class EventScrombler {
    
    /// Shared instance
    static let shared = EventScrombler()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Click a menu bar item reliably
    /// - Parameters:
    ///   - item: The menu bar item to click
    ///   - mouseButton: Mouse button to use (.left or .right)
    func clickItem(_ item: MenuBarItem, mouseButton: CGMouseButton = .left) async throws {
        print("[EventScrombler] Clicking \(item.displayName)")
        
        // Get current frame
        guard let currentFrame = MenuBarItem.getCurrentFrame(for: item.windowID),
              currentFrame.width > 0 else {
            print("[EventScrombler] Could not get frame for \(item.displayName)")
            throw EventError.eventDeliveryFailed
        }
        
        // Save cursor position
        guard let cursorLocation = CGEvent(source: nil)?.location else {
            throw EventError.invalidEventSource
        }
        
        // Create event source with proper settings
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw EventError.invalidEventSource
        }
        
        // Permit events during suppression states (critical for background apps)
        permitAllEvents(source: source)
        
        // Calculate click point (center of item)
        let clickPoint = CGPoint(x: currentFrame.midX, y: currentFrame.midY)
        
        // Get event types for mouse button
        let (downType, upType) = getEventTypes(for: mouseButton)
        
        // Create mouse events
        guard let mouseDownEvent = CGEvent(
            mouseEventSource: source,
            mouseType: downType,
            mouseCursorPosition: clickPoint,
            mouseButton: mouseButton
        ) else {
            throw EventError.eventCreationFailure
        }
        
        guard let mouseUpEvent = CGEvent(
            mouseEventSource: source,
            mouseType: upType,
            mouseCursorPosition: clickPoint,
            mouseButton: mouseButton
        ) else {
            throw EventError.eventCreationFailure
        }
        
        // Set target fields for specific PID targeting
        setEventTargetFields(mouseDownEvent, item: item)
        setEventTargetFields(mouseUpEvent, item: item)
        
        // Hide cursor
        CGDisplayHideCursor(CGMainDisplayID())
        
        defer {
            // Restore cursor
            CGWarpMouseCursorPosition(cursorLocation)
            CGDisplayShowCursor(CGMainDisplayID())
        }
        
        // Warp cursor to click point
        CGWarpMouseCursorPosition(clickPoint)
        
        // Small delay for warp
        try await Task.sleep(for: .milliseconds(10))
        
        // Scromble the events (route through event tap for reliable delivery)
        try await scrombleEvent(mouseDownEvent, targetPID: item.ownerPID)
        
        // Small delay between down and up
        try await Task.sleep(for: .milliseconds(50))
        
        try await scrombleEvent(mouseUpEvent, targetPID: item.ownerPID)
        
        print("[EventScrombler] Click complete for \(item.displayName)")
    }
    
    // MARK: - Private Implementation
    
    /// Configure event source to permit events during suppression
    private func permitAllEvents(source: CGEventSource) {
        // Allow local mouse events during all suppression states
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateRemoteMouseDrag
        )
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        source.localEventsSuppressionInterval = 0
    }
    
    /// Set target fields on event for specific PID delivery
    private func setEventTargetFields(_ event: CGEvent, item: MenuBarItem) {
        // Target the specific process
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(item.ownerPID))
        
        // Set window under mouse pointer
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(item.windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(item.windowID))
    }
    
    /// Get down/up event types for mouse button
    private func getEventTypes(for button: CGMouseButton) -> (down: CGEventType, up: CGEventType) {
        switch button {
        case .left: return (.leftMouseDown, .leftMouseUp)
        case .right: return (.rightMouseDown, .rightMouseUp)
        case .center: return (.otherMouseDown, .otherMouseUp)
        @unknown default: return (.leftMouseDown, .leftMouseUp)
        }
    }
    
    /// Ice-style scromble: route event through event tap for reliable delivery
    /// This creates a temporary event tap to intercept and reroute the event
    private func scrombleEvent(_ event: CGEvent, targetPID: pid_t) async throws {
        // Create proxy event source for routing
        guard let proxySource = CGEventSource(stateID: .combinedSessionState) else {
            throw EventError.invalidEventSource
        }
        
        // Create callback context
        let context = ScrombleContext(targetEvent: event, targetPID: targetPID)
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        
        defer {
            Unmanaged<ScrombleContext>.fromOpaque(contextPtr).release()
        }
        
        // Create event tap to receive our event
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.leftMouseUp.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseUp.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: scrombleCallback,
            userInfo: contextPtr
        ) else {
            throw EventError.eventTapCreationFailed
        }
        
        // Create run loop source
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        defer {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        
        // Post the event - it will be intercepted by our tap
        event.post(tap: .cgSessionEventTap)
        
        // Wait for delivery with timeout
        let timeout: TimeInterval = 0.5
        let startTime = Date()
        
        while !context.isDelivered && Date().timeIntervalSince(startTime) < timeout {
            // Run the run loop briefly to process events
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
            try await Task.sleep(for: .milliseconds(10))
        }
        
        if !context.isDelivered {
            // Fallback: just post directly without tap
            print("[EventScrombler] Event tap timeout, posting directly")
            event.post(tap: .cgSessionEventTap)
        }
    }
}

/// Context for scromble callback
private final class ScrombleContext {
    let targetEvent: CGEvent
    let targetPID: pid_t
    var isDelivered = false
    
    init(targetEvent: CGEvent, targetPID: pid_t) {
        self.targetEvent = targetEvent
        self.targetPID = targetPID
    }
}

/// Scromble callback - intercepts and reroutes events
private func scrombleCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }
    
    let context = Unmanaged<ScrombleContext>.fromOpaque(userInfo).takeUnretainedValue()
    
    // Check if this is our event (compare locations as a simple check)
    let eventLocation = event.location
    let targetLocation = context.targetEvent.location
    
    if abs(eventLocation.x - targetLocation.x) < 1 && abs(eventLocation.y - targetLocation.y) < 1 {
        // This is our event - mark as delivered
        context.isDelivered = true
        
        // Set PID target and let it through
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(context.targetPID))
        
        return Unmanaged.passUnretained(event)
    }
    
    return Unmanaged.passUnretained(event)
}
