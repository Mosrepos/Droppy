//
//  DroppyBarPanel.swift
//  Droppy
//
//  Ice-style floating bar that shows hidden menu bar icons.
//  Uses MenuBarItemImageCache for icons and MenuBarItemClicker for clicks.
//

import Cocoa
import SwiftUI

/// A floating panel that displays overflow menu bar icons below the main menu bar.
/// Styled like Ice's IceBar with capsule shape and proper icon handling.
@MainActor
final class DroppyBarPanel: NSPanel {
    
    /// Shared image cache
    let imageCache = MenuBarItemImageCache()
    
    /// The current screen
    private(set) var currentScreen: NSScreen?
    
    // MARK: - Initialization
    
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        setupPanel()
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
    
    // MARK: - Show/Hide
    
    /// Show the panel on the specified screen
    func show(on screen: NSScreen? = nil) async {
        // Find the screen with the mouse cursor if not specified
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = screen ?? NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        
        guard let targetScreen = targetScreen else { return }
        
        currentScreen = targetScreen
        
        // Update image cache before showing
        await imageCache.updateCache()
        
        // Create content view
        let hostingView = DroppyBarHostingView(
            rootView: DroppyBarContentView(imageCache: imageCache, closePanel: { [weak self] in
                self?.close()
            })
        )
        contentView = hostingView
        
        // Position and show
        updateOrigin(for: targetScreen)
        orderFrontRegardless()
        
        print("[DroppyBar] Shown on screen: \(targetScreen.localizedName)")
    }
    
    /// Update the panel position for the given screen
    private func updateOrigin(for screen: NSScreen) {
        let menuBarHeight: CGFloat = 24
        
        // Calculate origin Y: just below menu bar
        let originY = (screen.frame.maxY - 1) - menuBarHeight - frame.height
        
        // Calculate origin X: right side of screen, with padding
        let originX = screen.frame.maxX - frame.width - 8
        
        setFrameOrigin(CGPoint(x: originX, y: originY))
    }
    
    override func close() {
        super.close()
        contentView = nil
        currentScreen = nil
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
    @ObservedObject var imageCache: MenuBarItemImageCache
    let closePanel: () -> Void
    
    @State private var items: [MenuBarItem] = []
    
    private var contentHeight: CGFloat {
        imageCache.menuBarHeight ?? 24
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if items.isEmpty {
                if !CGPreflightScreenCaptureAccess() {
                    Text("Screen recording required")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                } else {
                    Text("No hidden icons")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                }
            } else {
                ForEach(items) { item in
                    DroppyBarItemView(
                        item: item,
                        imageCache: imageCache,
                        closePanel: closePanel
                    )
                }
            }
        }
        .frame(height: contentHeight)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        // Ice-style capsule background
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(Capsule(style: .continuous))
        .shadow(color: .black.opacity(0.33), radius: 2.5)
        .padding(5)
        .fixedSize()
        .onAppear {
            loadItems()
        }
    }
    
    private func loadItems() {
        // Get menu bar items - for now get all, later filter to hidden only
        items = MenuBarItem.getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)
            .filter { item in
                // Filter out our own app's items
                item.ownerName != "Droppy" &&
                item.ownerName != "Control Center" &&
                item.ownerName != "Spotlight"
            }
        print("[DroppyBar] Loaded \(items.count) items")
    }
}

// MARK: - DroppyBarItemView

/// A single menu bar item in the Droppy Bar
struct DroppyBarItemView: View {
    let item: MenuBarItem
    @ObservedObject var imageCache: MenuBarItemImageCache
    let closePanel: () -> Void
    
    private var image: NSImage? {
        imageCache.getImage(for: item)
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback: show app icon
                if let app = item.owningApplication,
                   let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                }
            }
        }
        .contentShape(Rectangle())
        .overlay {
            DroppyBarItemClickHandler(item: item, closePanel: closePanel)
        }
        .help(item.displayName)
    }
}

// MARK: - DroppyBarItemClickHandler

/// NSViewRepresentable that handles clicks on bar items
struct DroppyBarItemClickHandler: NSViewRepresentable {
    let item: MenuBarItem
    let closePanel: () -> Void
    
    func makeNSView(context: Context) -> DroppyBarClickView {
        DroppyBarClickView(item: item, closePanel: closePanel)
    }
    
    func updateNSView(_ nsView: DroppyBarClickView, context: Context) {}
}

/// NSView that handles mouse events
final class DroppyBarClickView: NSView {
    let item: MenuBarItem
    let closePanel: () -> Void
    
    private var lastLeftMouseDownDate = Date.now
    private var lastRightMouseDownDate = Date.now
    private var lastLeftMouseDownLocation = CGPoint.zero
    private var lastRightMouseDownLocation = CGPoint.zero
    
    init(item: MenuBarItem, closePanel: @escaping () -> Void) {
        self.item = item
        self.closePanel = closePanel
        super.init(frame: .zero)
        self.toolTip = item.displayName
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
        handleClick(mouseButton: .left)
    }
    
    override func rightMouseUp(with event: NSEvent) {
        super.rightMouseUp(with: event)
        guard
            Date.now.timeIntervalSince(lastRightMouseDownDate) < 0.5,
            absoluteDistance(lastRightMouseDownLocation, NSEvent.mouseLocation) < 5
        else {
            return
        }
        handleClick(mouseButton: .right)
    }
    
    private func handleClick(mouseButton: CGMouseButton) {
        // Close the panel first (like Ice does)
        closePanel()
        
        // Small delay then click the item
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(25))
            MenuBarItemClicker.shared.clickItem(item, mouseButton: mouseButton)
        }
    }
}
