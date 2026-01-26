//
//  DroppyBarPanel.swift
//  Droppy
//
//  A beautiful floating panel that appears below the menu bar to display overflow icons.
//

import Cocoa
import SwiftUI

/// A floating panel that displays overflow menu bar icons below the main menu bar.
@MainActor
final class DroppyBarPanel: NSPanel {
    
    // MARK: - Properties
    
    /// The height of the Droppy Bar
    private let barHeight: CGFloat = 36
    
    /// Padding from the right edge of the screen
    private let rightPadding: CGFloat = 12
    
    /// Whether the panel should auto-hide when mouse leaves (disabled by default)
    var autoHideEnabled: Bool = false
    
    // MARK: - Initialization
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: barHeight),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        setupPanel()
        setupContentView()
    }
    
    private func setupPanel() {
        // Panel appearance
        title = "Droppy Bar"
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        backgroundColor = .clear
        hasShadow = true
        
        // Floating behavior
        level = .statusBar + 1
        isFloatingPanel = true
        hidesOnDeactivate = false
        
        // Collection behavior
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        
        // Don't become key window
        becomesKeyOnlyIfNeeded = true
    }
    
    private func setupContentView() {
        let hostingView = NSHostingView(rootView: DroppyBarContentView())
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }
    
    // MARK: - Positioning
    
    /// Show the panel on the specified screen
    func show(on screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let targetScreen = targetScreen else { return }
        
        updatePosition(for: targetScreen)
        orderFrontRegardless()
        
        print("[DroppyBar] Shown on screen: \(targetScreen.localizedName)")
    }
    
    /// Update the panel position for the given screen
    func updatePosition(for screen: NSScreen) {
        let menuBarHeight: CGFloat = 24
        
        // Calculate width based on content, min 200, max 500
        let panelWidth = min(max(200, screen.frame.width * 0.25), 500)
        
        // Position: right side of screen, just below menu bar
        let x = screen.frame.maxX - panelWidth - rightPadding
        let y = screen.frame.maxY - menuBarHeight - barHeight - 6
        
        setFrame(NSRect(x: x, y: y, width: panelWidth, height: barHeight), display: true)
    }
}

// MARK: - DroppyBarContentView

/// SwiftUI content view for the Droppy Bar - premium glassmorphism design
struct DroppyBarContentView: View {
    @StateObject private var scanner = MenuBarItemScanner()
    @State private var hoveredItemID: Int?
    @State private var isHoveringRefresh = false
    
    var body: some View {
        HStack(spacing: 2) {
            // Left gradient accent
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 8)
            
            // Menu bar items
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    if scanner.menuBarItems.isEmpty && !scanner.isScanning {
                        Text("No items")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                    } else if scanner.isScanning {
                        ProgressView()
                            .scaleEffect(0.6)
                            .padding(.horizontal, 8)
                    } else {
                        ForEach(scanner.menuBarItems) { item in
                            DroppyBarIconButton(
                                item: item,
                                isHovered: hoveredItemID == item.id,
                                onHover: { isHovered in
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        hoveredItemID = isHovered ? item.id : nil
                                    }
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 6)
            }
            
            Spacer(minLength: 4)
            
            // Separator
            Rectangle()
                .fill(.white.opacity(0.1))
                .frame(width: 1)
                .padding(.vertical, 10)
            
            // Refresh button
            Button(action: performScan) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isHoveringRefresh ? .primary : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(.white.opacity(isHoveringRefresh ? 0.1 : 0))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringRefresh = $0 }
            .help("Refresh menu bar icons")
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                // Dark glassmorphism background
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                
                // Subtle gradient overlay
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.05),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
        .onAppear(perform: performScan)
    }
    
    private func performScan() {
        if scanner.hasScreenCapturePermission {
            scanner.scanWithCapture()
        } else {
            scanner.scan()
        }
    }
}

// MARK: - DroppyBarIconButton

/// A beautiful button that displays a menu bar item icon
struct DroppyBarIconButton: View {
    let item: MenuBarItemScanner.ScannedMenuItem
    let isHovered: Bool
    let onHover: (Bool) -> Void
    
    var body: some View {
        Button(action: activateMenuItem) {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                } else {
                    // Fallback: stylized letter
                    Text(String(item.ownerName.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                }
            }
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.15 : 0))
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .help(item.ownerName)
        .onHover(perform: onHover)
    }
    
    private func activateMenuItem() {
        if let app = NSRunningApplication(processIdentifier: pid_t(item.ownerPID)) {
            app.activate()
            print("[DroppyBar] Activated: \(item.ownerName)")
        }
    }
}

// MARK: - VisualEffectBlur

/// NSVisualEffectView wrapper for SwiftUI
struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
