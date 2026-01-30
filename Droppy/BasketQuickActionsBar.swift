//
//  BasketQuickActionsBar.swift
//  Droppy
//
//  Quick Actions bar - simple, snappy animation
//  Supports transparency mode
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Quick Actions Bar

struct BasketQuickActionsBar: View {
    let items: [DroppedItem]
    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground
    @State private var isExpanded = false
    @State private var isHovering = false
    @State private var isBoltTargeted = false  // Track when files are dragged over collapsed bolt
    
    private let buttonSize: CGFloat = 48
    private let spacing: CGFloat = 12
    
    // Colors based on transparency mode
    private var buttonFill: Color {
        useTransparentBackground ? Color.white.opacity(0.12) : Color.black
    }
    @State private var isBarAreaTargeted = false  // Track when drag is over the bar area (between buttons)
    
    /// Computed width of expanded bar area: 4 buttons + 3 gaps
    private var expandedBarWidth: CGFloat {
        (buttonSize * 4) + (spacing * 3) + 16  // Extra padding for safety
    }
    
    var body: some View {
        ZStack {
            // Transparent hit area background - captures drags between buttons AND clears state when drag exits
            if isExpanded {
                Capsule()
                    .fill(Color.white.opacity(0.001)) // Nearly invisible but captures events
                    .frame(width: expandedBarWidth, height: buttonSize + 8)
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                    // Track when drag is over the bar area
                    // Include file promise types for Photos.app compatibility
                    .onDrop(of: [UTType.fileURL, UTType.image, UTType.movie, UTType.data], isTargeted: $isBarAreaTargeted) { _ in
                        return false  // Don't handle drop here
                    }
                    // Clear global state when drag exits the bar area
                    .onChange(of: isBarAreaTargeted) { _, targeted in
                        if !targeted {
                            // Drag left the bar area - clear the global targeting state
                            DroppyState.shared.isQuickActionsTargeted = false
                        }
                    }
            }
            
            HStack(spacing: spacing) {
                if isExpanded {
                    // Expanded: Floating buttons only
                    QuickDropActionButton(actionType: .airdrop, useTransparent: useTransparentBackground, shareAction: shareViaAirDrop)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity).animation(DroppyAnimation.itemInsertion),
                            removal: .scale(scale: 0.5).combined(with: .opacity).animation(.easeOut(duration: 0.15))
                        ))
                    QuickDropActionButton(actionType: .messages, useTransparent: useTransparentBackground, shareAction: shareViaMessages)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity).animation(DroppyAnimation.itemInsertion.delay(0.03)),
                            removal: .scale(scale: 0.5).combined(with: .opacity).animation(.easeOut(duration: 0.15))
                        ))
                    QuickDropActionButton(actionType: .mail, useTransparent: useTransparentBackground, shareAction: shareViaMail)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity).animation(DroppyAnimation.itemInsertion.delay(0.06)),
                            removal: .scale(scale: 0.5).combined(with: .opacity).animation(.easeOut(duration: 0.15))
                        ))
                    QuickDropActionButton(actionType: .quickshare, useTransparent: useTransparentBackground, shareAction: quickShareTo0x0)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.5).combined(with: .opacity).animation(DroppyAnimation.itemInsertion.delay(0.09)),
                            removal: .scale(scale: 0.5).combined(with: .opacity).animation(.easeOut(duration: 0.15))
                        ))
                } else {
                    // Collapsed: Zap button - matches quick action icons with glass material
                    Circle()
                        .fill(useTransparentBackground ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.black))
                        .frame(width: buttonSize, height: buttonSize)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isBoltTargeted ? 0.3 : (useTransparentBackground ? 0.12 : 0.06)), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white.opacity(isBoltTargeted ? 1.0 : 0.85))
                        )
                        .scaleEffect(isBoltTargeted ? 1.15 : 1.0)
                        .contentShape(Circle().scale(1.3))
                        // DRAG-TO-EXPAND: Detect when files are dragged over the collapsed bolt
                        // Include file promise types for Photos.app compatibility
                        .onDrop(of: [UTType.fileURL, UTType.image, UTType.movie, UTType.data], isTargeted: $isBoltTargeted) { _ in
                            // Don't handle the drop here - just expand so user can drop on specific action
                            return false
                        }
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                        .animation(DroppyAnimation.hoverBouncy, value: isBoltTargeted)
                }
            }
        }
        .animation(DroppyAnimation.state, value: isExpanded)
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: isHovering) { _, hovering in
            // EXPANDED VIA HOVER: normal expand/collapse on hover
            // But don't collapse if still dragging over quick action buttons
            if !hovering && (DroppyState.shared.isQuickActionsTargeted || isBoltTargeted) {
                return  // Keep expanded while dragging over bar
            }
            withAnimation(DroppyAnimation.state) {
                isExpanded = hovering
            }
            // Clear hovered action when collapsing
            if !hovering {
                DroppyState.shared.hoveredQuickAction = nil
            }
            if hovering && !isExpanded {
                HapticFeedback.expand()
            }
        }
        // DRAG-TO-EXPAND: Auto-expand when files are dragged over the collapsed bolt
        .onChange(of: isBoltTargeted) { _, targeted in
            if targeted && !isExpanded {
                withAnimation(DroppyAnimation.state) {
                    isExpanded = true
                }
                HapticFeedback.expand()
            }
        }
        // COLLAPSE when quick action targeting ends (drag left the buttons)
        .onChange(of: DroppyState.shared.isQuickActionsTargeted) { _, targeted in
            if !targeted && !isHovering && isExpanded {
                DroppyState.shared.hoveredQuickAction = nil
                withAnimation(DroppyAnimation.state) {
                    isExpanded = false
                }
            }
        }
        // COLLAPSE when basket becomes targeted (drag moved to basket area)
        .onChange(of: DroppyState.shared.isBasketTargeted) { _, targeted in
            if targeted && isExpanded {
                // Drag moved to basket - collapse back to bolt and clear quick actions state
                DroppyState.shared.isQuickActionsTargeted = false
                DroppyState.shared.hoveredQuickAction = nil
                withAnimation(DroppyAnimation.state) {
                    isExpanded = false
                }
            }
        }
    }
    
    // MARK: - Share Actions
    
    private func shareViaAirDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
        FloatingBasketWindowController.shared.hideBasket()
    }
    
    private func shareViaMessages(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .composeMessage)?.perform(withItems: urls)
        FloatingBasketWindowController.shared.hideBasket()
    }
    
    private func shareViaMail(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .composeEmail)?.perform(withItems: urls)
        FloatingBasketWindowController.shared.hideBasket()
    }
    
    /// Droppy Quickshare - uploads files to 0x0.st and copies shareable link to clipboard
    /// Multiple files are automatically zipped into a single archive
    private func quickShareTo0x0(_ urls: [URL]) {
        DroppyQuickshare.share(urls: urls) {
            FloatingBasketWindowController.shared.hideBasket()
        }
    }
}

// MARK: - Quick Drop Action Button

struct QuickDropActionButton: View {
    let actionType: QuickActionType
    var useTransparent: Bool = false
    let shareAction: ([URL]) -> Void
    
    @State private var isHovering = false
    @State private var isTargeted = false
    
    private let size: CGFloat = 48
    
    // Border opacity matches basket: 0.12 when transparent, 0.06 when solid
    private var borderOpacity: Double {
        if isTargeted { return 0.3 }
        if isHovering { return 0.2 }
        return useTransparent ? 0.12 : 0.06
    }
    
    var body: some View {
        // Use AppKit-based drop target for reliable Photos.app file promise support
        FilePromiseDropTarget(isTargeted: $isTargeted, onFilesReceived: { urls in
            shareAction(urls)
        }) {
            Circle()
                .fill(useTransparent ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.black))
                .frame(width: size, height: size)
                .overlay(
                    // Border matches basket style exactly
                    Circle()
                        .stroke(Color.white.opacity(borderOpacity), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: actionType.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                )
                // Grow when file dragged over
                .scaleEffect(isTargeted ? 1.18 : (isHovering ? 1.05 : 1.0))
                .animation(DroppyAnimation.hoverBouncy, value: isTargeted)
                .animation(DroppyAnimation.hoverBouncy, value: isHovering)
        }
        .onHover { hovering in
            isHovering = hovering
            // Update shared state for basket explanation overlay
            if hovering {
                DroppyState.shared.hoveredQuickAction = actionType
            } else if DroppyState.shared.hoveredQuickAction == actionType {
                DroppyState.shared.hoveredQuickAction = nil
            }
        }
        .frame(width: size, height: size)
        // CRITICAL: Update shared state when this button is targeted
        // Only SET the state - clearing is handled by capsule exit or basket targeting
        .onChange(of: isTargeted) { _, targeted in
            if targeted {
                DroppyState.shared.isQuickActionsTargeted = true
                DroppyState.shared.hoveredQuickAction = actionType
            }
            // Don't clear here - let capsule/basket handle it
        }
        .onTapGesture {
            let urls = DroppyState.shared.basketItems.map(\.url)
            if !urls.isEmpty {
                HapticFeedback.select()
                shareAction(urls)
            }
        }
    }
}


