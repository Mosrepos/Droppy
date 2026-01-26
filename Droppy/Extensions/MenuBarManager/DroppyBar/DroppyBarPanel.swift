//
//  DroppyBarPanel.swift
//  Droppy
//
//  Ice-style floating bar that shows hidden menu bar icons.
//  Icons are clickable and forward clicks to the actual menu bar items.
//

import Cocoa
import SwiftUI

/// A floating panel that displays overflow menu bar icons below the main menu bar.
/// Styled like Ice's IceBar with capsule shape and proper icon handling.
@MainActor
final class DroppyBarPanel: NSPanel {
    
    // MARK: - Properties
    
    /// The height of the Droppy Bar (matches menu bar height)
    private var barHeight: CGFloat {
        guard let screen = screen ?? NSScreen.main else { return 24 }
        return screen.getMenuBarHeight() ?? 24
    }
    
    // MARK: - Initialization
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 24),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        setupPanel()
        setupContentView()
    }
    
    private func setupPanel() {
        // Panel appearance - match Ice styling
        title = "Droppy Bar"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        allowsToolTipsWhenApplicationIsInactive = true
        backgroundColor = .clear
        hasShadow = false  // Shadow handled by SwiftUI
        
        // Floating behavior
        level = .mainMenu + 1
        isFloatingPanel = true
        hidesOnDeactivate = false
        animationBehavior = .none
        
        // Collection behavior
        collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle, .moveToActiveSpace]
        
        // Accept first mouse
        acceptsMouseMovedEvents = true
    }
    
    private func setupContentView() {
        let hostingView = DroppyBarHostingView(rootView: DroppyBarContentView())
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }
    
    // MARK: - Positioning
    
    /// Show the panel on the screen with the mouse
    func show(on screen: NSScreen? = nil) {
        // Find the screen with the mouse cursor if not specified
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = screen ?? NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first
        
        guard let targetScreen = targetScreen else { return }
        
        updatePosition(for: targetScreen)
        orderFrontRegardless()
        
        print("[DroppyBar] Shown on screen: \(targetScreen.localizedName)")
    }
    
    /// Update the panel position for the given screen (below menu bar, right side)
    func updatePosition(for screen: NSScreen) {
        let menuBarHeight = screen.getMenuBarHeight() ?? 24
        
        // Width based on content - will be adjusted by SwiftUI sizing
        let panelWidth: CGFloat = frame.width > 100 ? frame.width : 300
        
        // Position: right side of screen, just below menu bar
        let x = screen.frame.maxX - panelWidth - 8
        let y = (screen.frame.maxY - 1) - menuBarHeight - barHeight
        
        setFrameOrigin(CGPoint(x: x, y: y))
    }
    
    override func close() {
        super.close()
        contentView = nil
    }
}

// MARK: - DroppyBarHostingView

/// Custom hosting view that accepts first mouse
private final class DroppyBarHostingView: NSHostingView<DroppyBarContentView> {
    override var safeAreaInsets: NSEdgeInsets { NSEdgeInsets() }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

// MARK: - DroppyBarContentView

/// SwiftUI content view - Ice-style capsule bar with icons
struct DroppyBarContentView: View {
    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground
    @StateObject private var scanner = MenuBarItemScanner()
    @State private var frame = CGRect.zero
    
    private var contentHeight: CGFloat {
        NSScreen.main?.getMenuBarHeight() ?? 24
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if scanner.menuBarItems.isEmpty && !scanner.isScanning {
                Text("No hidden icons")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
            } else if scanner.isScanning {
                ProgressView()
                    .scaleEffect(0.6)
                    .padding(.horizontal, 12)
            } else {
                ForEach(scanner.menuBarItems) { item in
                    DroppyBarItemView(item: item)
                }
            }
        }
        .frame(height: contentHeight)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        // Ice-style capsule background
        .background(
            Capsule(style: .continuous)
                .fill(useTransparentBackground ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.black))
        )
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.33), radius: 2.5)
        .padding(5)
        .fixedSize()
        .onFrameChange(update: $frame)
        .onAppear {
            if scanner.hasScreenCapturePermission {
                scanner.scanWithCapture()
            } else {
                scanner.scan()
            }
        }
    }
}

// MARK: - DroppyBarItemView

/// A single menu bar item in the Droppy Bar - clickable to activate the real item
struct DroppyBarItemView: View {
    let item: MenuBarItemScanner.ScannedMenuItem
    
    var body: some View {
        Group {
            if let icon = item.icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 18)
            }
        }
        .contentShape(Rectangle())
        .overlay {
            DroppyBarItemClickHandler(item: item)
        }
        .help(item.ownerName)
    }
}

// MARK: - DroppyBarItemClickHandler

/// NSViewRepresentable that handles left and right clicks on bar items
struct DroppyBarItemClickHandler: NSViewRepresentable {
    let item: MenuBarItemScanner.ScannedMenuItem
    
    func makeNSView(context: Context) -> DroppyBarClickView {
        DroppyBarClickView(item: item)
    }
    
    func updateNSView(_ nsView: DroppyBarClickView, context: Context) {}
}

/// NSView that handles mouse events and forwards clicks to the actual menu bar item
final class DroppyBarClickView: NSView {
    let item: MenuBarItemScanner.ScannedMenuItem
    
    private var lastLeftMouseDownDate = Date.now
    private var lastRightMouseDownDate = Date.now
    private var lastLeftMouseDownLocation = CGPoint.zero
    private var lastRightMouseDownLocation = CGPoint.zero
    
    init(item: MenuBarItemScanner.ScannedMenuItem) {
        self.item = item
        super.init(frame: .zero)
        self.toolTip = item.ownerName
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func absoluteDistance(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        hypot(p1.x - p2.x, p1.y - p2.y).magnitude
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        lastLeftMouseDownDate = .now
        lastLeftMouseDownLocation = NSEvent.mouseLocation
    }
    
    override func rightMouseDown(with event: NSEvent) {
        super.rightMouseDown(with: event)
        lastRightMouseDownDate = .now
        lastRightMouseDownLocation = NSEvent.mouseLocation
    }
    
    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard
            Date.now.timeIntervalSince(lastLeftMouseDownDate) < 0.5,
            absoluteDistance(lastLeftMouseDownLocation, NSEvent.mouseLocation) < 5
        else {
            return
        }
        clickMenuItem(button: .left)
    }
    
    override func rightMouseUp(with event: NSEvent) {
        super.rightMouseUp(with: event)
        guard
            Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
            absoluteDistance(lastRightMouseDownLocation, NSEvent.mouseLocation) < 5
        else {
            return
        }
        clickMenuItem(button: .right)
    }
    
    /// Click the actual menu bar item by posting a click event to its position
    private func clickMenuItem(button: NSEvent.ButtonNumber) {
        Task { @MainActor in
            // Get the item's position in the menu bar
            guard let frame = item.frame else {
                // Fallback: just activate the app
                if let app = NSRunningApplication(processIdentifier: pid_t(item.ownerPID)) {
                    app.activate()
                }
                return
            }
            
            // Calculate click position (center of the item)
            let clickX = frame.midX
            let clickY = frame.midY
            
            // Post a mouse click event at the item's location
            // First, we need to convert to screen coordinates for CGEvent
            guard let screen = NSScreen.main else { return }
            let screenHeight = screen.frame.height
            let cgClickY = screenHeight - clickY  // Flip for CG coordinate system
            
            let clickPoint = CGPoint(x: clickX, y: cgClickY)
            
            // Create and post mouse events
            let mouseDownType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
            let mouseUpType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
            let mouseButton: CGMouseButton = button == .left ? .left : .right
            
            if let mouseDown = CGEvent(mouseEventSource: nil, mouseType: mouseDownType, mouseCursorPosition: clickPoint, mouseButton: mouseButton) {
                mouseDown.post(tap: .cghidEventTap)
            }
            
            try? await Task.sleep(for: .milliseconds(50))
            
            if let mouseUp = CGEvent(mouseEventSource: nil, mouseType: mouseUpType, mouseCursorPosition: clickPoint, mouseButton: mouseButton) {
                mouseUp.post(tap: .cghidEventTap)
            }
            
            print("[DroppyBar] Clicked \(item.ownerName) at (\(clickX), \(clickY)) with \(button == .left ? "left" : "right") button")
        }
    }
}

// MARK: - Helper Extension

extension NSScreen {
    /// Get the height of the menu bar on this screen
    func getMenuBarHeight() -> CGFloat? {
        return 24  // Standard menu bar height
    }
}
