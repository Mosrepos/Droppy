//
//  Parallax3DModifier.swift
//  Droppy
//
//  3D tilt parallax effect inspired by premium
//  Adds subtle rotation on hover tracking mouse position
//

import SwiftUI

/// 3D Parallax effect that tilts the view based on mouse position during hover.
/// Creates a premium, interactive feel similar to premium's implementation.
struct Parallax3DModifier: ViewModifier {
    /// Tilt magnitude in degrees (default: 10)
    var magnitude: Double
    
    /// Optional override for enabling/disabling (nil uses default enabled)
    var enableOverride: Bool?
    
    /// Suspend the effect temporarily (e.g., during other animations)
    var isSuspended: Bool
    
    @AppStorage(AppPreferenceKey.enableParallaxEffect) private var enableParallaxEffect = false
    @State private var offset: CGSize = .zero
    @State private var isHovering = false
    @State private var viewSize: CGSize = .zero
    
    func body(content: Content) -> some View {
        // Check if effect should be active
        let enabled = enableOverride ?? enableParallaxEffect
        
        if isSuspended || !enabled {
            content
        } else {
            content
                .contentShape(Rectangle())
                .overlay(
                    GeometryReader { proxy in
                        Color.clear
                            .allowsHitTesting(false)
                            .onAppear { viewSize = proxy.size }
                            .onChange(of: proxy.size) { _, newSize in
                                viewSize = newSize
                            }
                    }
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        // Skip hover math while clicking to avoid lag
                        guard viewSize.width > 0, viewSize.height > 0 else { return }
                        guard NSEvent.pressedMouseButtons == 0 else { return }
                        
                        // Normalize mouse position to -1...1 range
                        let x = (location.x / viewSize.width) * 2 - 1
                        let y = (location.y / viewSize.height) * 2 - 1
                        let nextOffset = CGSize(width: x, height: y)
                        let dx = nextOffset.width - offset.width
                        let dy = nextOffset.height - offset.height
                        let movedEnough = (dx * dx + dy * dy) > 0.0004

                        guard movedEnough || !isHovering else { return }
                        
                        // BUTTERY SMOOTH: Higher response for fluid tracking, smoother damping
                        withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.7, blendDuration: 0.1)) {
                            offset = nextOffset
                            isHovering = true
                        }
                        
                    case .ended:
                        // Smooth settle back with slightly longer spring
                        withAnimation(DroppyAnimation.transition) {
                            offset = .zero
                            isHovering = false
                        }
                    }
                }
                // X rotation based on vertical mouse position
                .rotation3DEffect(
                    .degrees(offset.height * magnitude),
                    axis: (x: 1, y: 0, z: 0)
                )
                // Y rotation based on horizontal mouse position (inverted for natural feel)
                .rotation3DEffect(
                    .degrees(offset.width * -magnitude),
                    axis: (x: 0, y: 1, z: 0)
                )
                // Subtle scale up on hover
                .scaleEffect(isHovering ? 1.02 : 1.0)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Adds a 3D parallax tilt effect on hover.
    /// - Parameters:
    ///   - magnitude: Tilt amount in degrees (default: 10)
    ///   - enableOverride: Force enable/disable (nil uses preference)
    ///   - suspended: Temporarily disable during other animations
    func parallax3D(
        magnitude: Double = 10,
        enableOverride: Bool? = nil,
        suspended: Bool = false
    ) -> some View {
        modifier(Parallax3DModifier(
            magnitude: magnitude,
            enableOverride: enableOverride,
            isSuspended: suspended
        ))
    }
}
