//
//  DragMonitor.swift
//  Droppy
//
//  Created by Jordy Spruit on 02/01/2026.
//

import AppKit
import Combine

/// Monitors system-wide drag events to detect when files/items are being dragged
final class DragMonitor: ObservableObject {
    /// Shared instance for app-wide access
    static let shared = DragMonitor()
    
    /// Whether a drag operation with droppable content is in progress
    @Published private(set) var isDragging = false
    
    /// The current mouse location during drag
    @Published private(set) var dragLocation: CGPoint = .zero
    
    /// Whether a jiggle gesture was detected during drag (triggers basket)
    @Published private(set) var didJiggle = false
    
    private var isMonitoring = false
    private var dragStartChangeCount: Int = 0
    private var dragActive = false
    private var eventMonitors: [Any] = []
    
    // Jiggle detection state
    private var lastDragLocation: CGPoint = .zero
    private var lastDragDirection: CGPoint = .zero
    private var directionChanges: [Date] = []
    private let jiggleThreshold: Int = 3
    private let jiggleTimeWindow: TimeInterval = 0.5
    
    // Flags to prevent duplicate notifications
    private var jiggleNotified = false
    private var dragEndNotified = false
    
    private init() {}
    
    /// Starts monitoring for drag events
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        
        // 1. Global Monitors (captures events when OTHER apps are active)
        let gDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDragEvent(event)
        }
        
        let gMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
        }
        
        // 2. Local Monitors (captures events when DROPPY is active, e.g. Clipboard open)
        let lDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleDragEvent(event)
            return event
        }
        
        let lMouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.handleMouseUp(event)
            return event
        }
        
        if let m = gDragMonitor { eventMonitors.append(m) }
        if let m = gMouseUpMonitor { eventMonitors.append(m) }
        if let m = lDragMonitor { eventMonitors.append(m) }
        if let m = lMouseUpMonitor { eventMonitors.append(m) }
    }
    
    /// Stops monitoring for drag events
    func stopMonitoring() {
        isMonitoring = false
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
    }
    
    private func handleDragEvent(_ event: NSEvent) {
        autoreleasepool {
            let currentMouseLocation = NSEvent.mouseLocation
            let dragPasteboard = NSPasteboard(name: .drag)
            let currentChangeCount = dragPasteboard.changeCount
            
            // Detect drag START
            if currentChangeCount != dragStartChangeCount {
                let hasContent = (dragPasteboard.types?.count ?? 0) > 0
                if hasContent && !dragActive {
                    dragActive = true
                    dragStartChangeCount = currentChangeCount
                    resetJiggle()
                    dragEndNotified = false
                    lastDragLocation = currentMouseLocation
                    isDragging = true
                }
            }
            
            // Update location while dragging
            if dragActive {
                dragLocation = currentMouseLocation
                detectJiggle(currentLocation: currentMouseLocation)
                lastDragLocation = currentMouseLocation
            }
        }
    }
    
    private func handleMouseUp(_ event: NSEvent) {
        guard dragActive else { return }
        
        dragActive = false
        isDragging = false
        dragEndNotified = true
        
        // Notify controller that drag ended
        FloatingBasketWindowController.shared.onDragEnded()
        
        resetJiggle()
    }
    
    /// Resets jiggle state (called after basket is shown or drag ends)
    func resetJiggle() {
        didJiggle = false
        jiggleNotified = false
        directionChanges.removeAll()
        lastDragDirection = .zero
    }

    
    private func detectJiggle(currentLocation: CGPoint) {
        let dx = currentLocation.x - lastDragLocation.x
        let dy = currentLocation.y - lastDragLocation.y
        let magnitude = sqrt(dx * dx + dy * dy)
        
        guard magnitude > 5 else { return }
        
        let currentDirection = CGPoint(x: dx / magnitude, y: dy / magnitude)
        
        if lastDragDirection != .zero {
            let dot = currentDirection.x * lastDragDirection.x + currentDirection.y * lastDragDirection.y
            
            if dot < -0.3 {
                let now = Date()
                directionChanges.append(now)
                directionChanges = directionChanges.filter { now.timeIntervalSince($0) < jiggleTimeWindow }
                
                if directionChanges.count >= jiggleThreshold && !jiggleNotified {
                    didJiggle = true
                    jiggleNotified = true
                    
                    // Allow re-notifying after a delay (to move basket)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.jiggleNotified = false
                    }
                    
                    // Use async to avoid blocking the timer
                    DispatchQueue.main.async {
                        // Check if basket is enabled before showing
                        let enabled = UserDefaults.standard.bool(forKey: "enableFloatingBasket")
                        if enabled || UserDefaults.standard.object(forKey: "enableFloatingBasket") == nil {
                            FloatingBasketWindowController.shared.onJiggleDetected()
                        }
                    }
                }
            }
        }
        
        lastDragDirection = currentDirection
    }
}
