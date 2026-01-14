import SwiftUI

/// Fixed color palette for dark mode UI (Droppy is dark mode only)
enum AdaptiveColors {
    /// Button background - subtle white overlay
    static let buttonBackgroundAuto = Color.white.opacity(0.1)
    
    /// Hover background - slightly brighter
    static let hoverBackgroundAuto = Color.white.opacity(0.15)
    
    /// Subtle border for cards and containers
    static let subtleBorderAuto = Color.white.opacity(0.1)
    
    /// Primary text color
    static let primaryTextAuto = Color.white
    
    /// Secondary text color
    static let secondaryTextAuto = Color.white.opacity(0.7)
}
