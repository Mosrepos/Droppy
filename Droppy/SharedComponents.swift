//
//  SharedComponents.swift
//  Droppy
//
//  Shared UI components used across SettingsView and OnboardingView
//  Consolidated to maintain consistency and reduce code duplication
//

import SwiftUI

// MARK: - Design Constants

/// Centralized design constants for consistent styling
enum DesignConstants {
    static let buttonCornerRadius: CGFloat = 16
    static let innerPreviewRadius: CGFloat = 12
    static let springResponse: Double = 0.25
    static let springDamping: Double = 0.7
    static let bounceResponse: Double = 0.2
    static let bounceDamping: Double = 0.4
}

// MARK: - Option Button Style

/// Shared button style with press animation
struct OptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: - Animated HUD Toggle

/// Reusable HUD toggle button with icon bounce animation
/// Used in both OnboardingView and SettingsView for HUD option grids
struct AnimatedHUDToggle: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var color: Color = .green
    var fixedWidth: CGFloat? = 100  // nil = flexible (fills container)
    
    @State private var iconBounce = false
    @State private var isHovering = false
    
    private var borderColor: Color {
        if isHovering {
            return isOn ? color.opacity(0.7) : Color.white.opacity(0.3)
        } else {
            return isOn ? color.opacity(0.5) : Color.white.opacity(0.1)
        }
    }
    
    var body: some View {
        Button {
            // Trigger icon bounce
            withAnimation(.spring(response: DesignConstants.bounceResponse, dampingFraction: DesignConstants.bounceDamping)) {
                iconBounce = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    iconBounce = false
                    isOn.toggle()
                }
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isOn ? color : .secondary)
                    .scaleEffect(iconBounce ? 1.3 : 1.0)
                    .rotationEffect(.degrees(iconBounce ? -8 : 0))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isOn ? .white : .secondary)
            }
            .frame(width: fixedWidth, height: 80)
            .frame(maxWidth: fixedWidth == nil ? .infinity : nil)
            .background(Color.white.opacity(isOn ? 0.1 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : (isOn ? 1.0 : 0.98))
            .animation(.spring(response: DesignConstants.springResponse, dampingFraction: DesignConstants.springDamping), value: isHovering)
        }
        .buttonStyle(OptionButtonStyle())
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Animated HUD Toggle with Subtitle

/// HUD toggle with subtitle text and icon bounce animation
/// Used for toggles that need to show connection to another toggle (e.g., Auto-Hide for Media)
struct AnimatedHUDToggleWithSubtitle: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var color: Color = .pink
    var isEnabled: Bool = true
    
    @State private var iconBounce = false
    @State private var isHovering = false
    
    private var borderColor: Color {
        if isHovering && isEnabled {
            return isOn ? color.opacity(0.7) : Color.white.opacity(0.3)
        } else {
            return isOn ? color.opacity(0.5) : Color.white.opacity(0.1)
        }
    }
    
    var body: some View {
        Button {
            guard isEnabled else { return }
            // Trigger icon bounce
            withAnimation(.spring(response: DesignConstants.bounceResponse, dampingFraction: DesignConstants.bounceDamping)) {
                iconBounce = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    iconBounce = false
                    isOn.toggle()
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isOn ? color : .secondary)
                    .scaleEffect(iconBounce ? 1.3 : 1.0)
                    .rotationEffect(.degrees(iconBounce ? -8 : 0))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isOn ? .white : .secondary)
                Text(subtitle)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(Color.white.opacity(isOn ? 0.1 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(isHovering && isEnabled ? 1.02 : (isOn ? 1.0 : 0.98))
            .animation(.spring(response: DesignConstants.springResponse, dampingFraction: DesignConstants.springDamping), value: isHovering)
        }
        .buttonStyle(OptionButtonStyle())
        .contentShape(Rectangle())
        .disabled(!isEnabled)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Volume & Brightness Toggle

/// Special toggle for Volume/Brightness that morphs between icons on tap
/// Used in both SettingsView and OnboardingView HUD options
struct VolumeAndBrightnessToggle: View {
    @Binding var isEnabled: Bool
    
    @State private var showBrightnessIcon = false
    @State private var iconBounce = false
    @State private var isHovering = false
    
    private var borderColor: Color {
        if isHovering {
            return isEnabled ? Color.white.opacity(0.7) : Color.white.opacity(0.3)
        } else {
            return isEnabled ? Color.white.opacity(0.5) : Color.white.opacity(0.1)
        }
    }
    
    var body: some View {
        Button {
            // Trigger icon morph animation
            withAnimation(.spring(response: DesignConstants.bounceResponse, dampingFraction: DesignConstants.bounceDamping)) {
                iconBounce = true
                showBrightnessIcon = true
            }
            
            // Switch back to volume after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    showBrightnessIcon = false
                }
            }
            
            // Toggle state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    iconBounce = false
                    isEnabled.toggle()
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Volume icon
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.title2)
                        .foregroundStyle(isEnabled ? .white : .secondary)
                        .opacity(showBrightnessIcon ? 0 : 1)
                        .scaleEffect(showBrightnessIcon ? 0.5 : 1)
                    
                    // Brightness icon (shown briefly on tap)
                    Image(systemName: "sun.max.fill")
                        .font(.title2)
                        .foregroundStyle(isEnabled ? .yellow : .secondary)
                        .opacity(showBrightnessIcon ? 1 : 0)
                        .scaleEffect(showBrightnessIcon ? 1 : 0.5)
                }
                .scaleEffect(iconBounce ? 1.3 : 1.0)
                .rotationEffect(.degrees(iconBounce ? -8 : 0))
                
                Text("Volume & Brightness")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isEnabled ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(Color.white.opacity(isEnabled ? 0.1 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : (isEnabled ? 1.0 : 0.98))
            .animation(.spring(response: DesignConstants.springResponse, dampingFraction: DesignConstants.springDamping), value: isHovering)
        }
        .buttonStyle(OptionButtonStyle())
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Display Mode Button

/// Reusable button for Notch/Dynamic Island mode selection with hover and press animations
/// Used in both SettingsView and OnboardingView for display mode picker
struct DisplayModeButton<Icon: View>: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let icon: Icon
    let action: () -> Void
    
    @State private var isHovering = false
    @State private var isPressed = false
    @State private var iconBounce = false
    
    init(title: String, subtitle: String? = nil, isSelected: Bool, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.icon = icon()
        self.action = action
    }
    
    private var borderColor: Color {
        if isHovering {
            return isSelected ? Color.blue.opacity(0.7) : Color.white.opacity(0.3)
        } else {
            return isSelected ? Color.blue.opacity(0.5) : Color.white.opacity(0.1)
        }
    }
    
    var body: some View {
        Button(action: {
            // Trigger icon bounce animation
            withAnimation(.spring(response: DesignConstants.bounceResponse, dampingFraction: DesignConstants.bounceDamping)) {
                iconBounce = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    iconBounce = false
                    action()
                }
            }
        }) {
            VStack(spacing: 8) {
                // Icon preview area
                ZStack {
                    RoundedRectangle(cornerRadius: DesignConstants.innerPreviewRadius, style: .continuous)
                        .fill(isSelected ? Color.blue.opacity(0.3) : Color.white.opacity(0.1))
                        .frame(width: 100, height: 50)
                    
                    icon
                        .scaleEffect(iconBounce ? 1.2 : 1.0)
                        .rotationEffect(.degrees(iconBounce ? -5 : 0))
                }
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.15) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
            )
            .scaleEffect(isPressed ? 0.97 : (isHovering ? 1.02 : 1.0))
            .animation(.spring(response: DesignConstants.springResponse, dampingFraction: DesignConstants.springDamping), value: isHovering)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

// MARK: - Animated Sub-Setting Toggle

/// Sub-setting toggle with icon bounce animation and subtitle
/// Used in OnboardingView for shelf sub-options
struct AnimatedSubSettingToggle: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var color: Color = .green
    
    @State private var iconBounce = false
    @State private var isHovering = false
    
    private var borderColor: Color {
        if isHovering {
            return isOn ? color.opacity(0.7) : Color.white.opacity(0.3)
        } else {
            return isOn ? color.opacity(0.5) : Color.white.opacity(0.1)
        }
    }
    
    var body: some View {
        Button {
            // Trigger icon bounce
            withAnimation(.spring(response: DesignConstants.bounceResponse, dampingFraction: DesignConstants.bounceDamping)) {
                iconBounce = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    iconBounce = false
                    isOn.toggle()
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isOn ? color : .secondary)
                    .scaleEffect(iconBounce ? 1.3 : 1.0)
                    .rotationEffect(.degrees(iconBounce ? -8 : 0))
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isOn ? .white : .secondary)
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 140)
            .padding(.vertical, 12)
            .background(Color.white.opacity(isOn ? 0.1 : 0.05))
            .clipShape(RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignConstants.buttonCornerRadius, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : (isOn ? 1.0 : 0.98))
            .animation(.spring(response: DesignConstants.springResponse, dampingFraction: DesignConstants.springDamping), value: isHovering)
        }
        .buttonStyle(OptionButtonStyle())
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
