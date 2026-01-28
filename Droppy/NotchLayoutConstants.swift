//
//  NotchLayoutConstants.swift
//  Droppy
//
//  Single Source of Truth (SSOT) for notch/island layout calculations.
//  ALL expanded content views (MediaPlayer, TerminalNotch, ShelfView, etc.)
//  MUST use these constants for consistent padding.
//

import SwiftUI

/// Centralized layout constants for notch and Dynamic Island modes.
/// Use these for ALL expanded content padding to ensure perfect consistency.
enum NotchLayoutConstants {
    
    // MARK: - Content Padding (for expanded views like MediaPlayer, TerminalNotch, ShelfItems)
    
    /// Standard content padding (left, right, bottom) - equal on all three edges
    static let contentPadding: CGFloat = 20
    
    // MARK: - Dynamic Island Dimensions (collapsed state)
    
    /// Dynamic Island collapsed width
    static let dynamicIslandWidth: CGFloat = 210
    
    /// Dynamic Island collapsed height
    static let dynamicIslandHeight: CGFloat = 37
    
    /// Dynamic Island top margin from screen edge (creates floating effect like iPhone)
    static let dynamicIslandTopMargin: CGFloat = 4
    
    // MARK: - Physical Notch Dimensions
    
    /// Physical notch width (Apple's standard design)
    static let physicalNotchWidth: CGFloat = 180
    
    // MARK: - Floating Button Spacing
    
    /// Gap between expanded content and floating buttons below
    /// Used for buttons like close, terminal toggle, settings etc.
    static let floatingButtonGap: CGFloat = 12
    
    /// Extra offset for island mode floating buttons to match notch mode visual spacing
    /// In notch mode, currentExpandedHeight includes top padding compensation which naturally
    /// pushes buttons lower. Island mode needs this extra offset to match.
    static let floatingButtonIslandCompensation: CGFloat = 6
    
    // MARK: - Notch Mode Calculations
    
    /// Standard MacBook Pro notch height (menu bar safe area height)
    /// This is consistent across all notch MacBooks at their default resolution
    static let physicalNotchHeight: CGFloat = 37
    
    /// Get the physical notch height for a given screen
    /// Returns physicalNotchHeight as fallback when screen is unavailable
    /// CRITICAL: Uses auxiliary areas for detection (stable on lock screen) and
    /// returns the stable safeAreaInsets value when available, with a fixed fallback
    static func notchHeight(for screen: NSScreen?) -> CGFloat {
        // CRITICAL: Return physical notch height when screen is unavailable for stable positioning
        guard let screen = screen else { return physicalNotchHeight }
        
        // Use auxiliary areas to detect physical notch (stable on lock screen)
        let hasPhysicalNotch = screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        guard hasPhysicalNotch else { return 0 }
        
        // Return actual safeAreaInsets if available, otherwise use fixed constant
        let topInset = screen.safeAreaInsets.top
        return topInset > 0 ? topInset : physicalNotchHeight
    }
    
    /// Whether a screen is in Dynamic Island mode (no physical notch)
    /// Uses auxiliary areas for stable detection on lock screen
    /// CRITICAL: Returns false (notch mode) when screen is unavailable to prevent layout jumps
    static func isDynamicIslandMode(for screen: NSScreen?) -> Bool {
        guard let screen = screen else { return false }
        let hasPhysicalNotch = screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        return !hasPhysicalNotch
    }
    
    // MARK: - EdgeInsets Calculation
    
    /// Calculate content EdgeInsets for expanded views.
    /// - Notch mode: top = notchHeight (content starts JUST below the physical notch),
    ///               left/right/bottom = contentPadding (equal on all three)
    /// - Island mode: equal padding on ALL four edges
    ///
    /// - Parameter screen: The target screen (uses main if nil)
    /// - Returns: EdgeInsets for the content
    static func contentEdgeInsets(for screen: NSScreen?) -> EdgeInsets {
        let targetScreen = screen ?? NSScreen.main
        let notch = notchHeight(for: targetScreen)
        
        // Check if external display using notch visual style (has curved corners)
        let isExternalWithNotchStyle: Bool = {
            guard let s = targetScreen else { return false }
            if s.isBuiltIn { return false }
            let externalUseDI = UserDefaults.standard.object(forKey: "externalDisplayUseDynamicIsland") as? Bool ?? true
            return !externalUseDI
        }()
        
        if notch > 0 {
            // NOTCH MODE: Top padding = notchHeight + 10 (wing corner compensation)
            // Left/Right = contentPadding, Bottom = contentPadding - 10 (to balance)
            // The curved wing corners add 10pt visual inset at top corners
            return EdgeInsets(
                top: notch + 10,
                leading: contentPadding,
                bottom: contentPadding - 10,
                trailing: contentPadding
            )
        } else if isExternalWithNotchStyle {
            // EXTERNAL WITH NOTCH STYLE: +10pt horizontal for curved corners, normal vertical
            return EdgeInsets(
                top: contentPadding,
                leading: contentPadding + 10,
                bottom: contentPadding,
                trailing: contentPadding + 10
            )
        } else {
            // PURE ISLAND MODE: 100% symmetrical padding on all edges
            return EdgeInsets(
                top: contentPadding,
                leading: contentPadding,
                bottom: contentPadding,
                trailing: contentPadding
            )
        }
    }
    
    /// Convenience method when you only have notchHeight, not the full screen
    /// - Parameters:
    ///   - notchHeight: The physical notch height (0 for island mode)
    ///   - isExternalWithNotchStyle: Whether this is an external display with notch visual style
    /// - Returns: EdgeInsets for the content
    static func contentEdgeInsets(notchHeight: CGFloat, isExternalWithNotchStyle: Bool = false) -> EdgeInsets {
        if notchHeight > 0 {
            // NOTCH MODE: Top + 10pt wing compensation, Bottom - 10pt to balance
            return EdgeInsets(
                top: notchHeight + 10,
                leading: contentPadding,
                bottom: contentPadding - 10,
                trailing: contentPadding
            )
        } else if isExternalWithNotchStyle {
            // EXTERNAL WITH NOTCH STYLE: +10pt horizontal for curved corners, normal vertical
            return EdgeInsets(
                top: contentPadding,
                leading: contentPadding + 10,
                bottom: contentPadding,
                trailing: contentPadding + 10
            )
        } else {
            // PURE ISLAND MODE: 100% symmetrical
            return EdgeInsets(
                top: contentPadding,
                leading: contentPadding,
                bottom: contentPadding,
                trailing: contentPadding
            )
        }
    }
}
