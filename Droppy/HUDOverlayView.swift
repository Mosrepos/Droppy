//
//  HUDOverlayView.swift
//  Droppy
//
//  Created by Droppy on 05/01/2026.
//  System HUD replacement that expands inside the notch
//

import SwiftUI

// HUDContentType is defined in LiquidSlider.swift

/// Embedded HUD view that appears inside the expanded notch
/// Icon on left, percentage on right, slider at bottom
struct NotchHUDView: View {
    @Binding var hudType: HUDContentType
    @Binding var value: CGFloat
    var onValueChange: ((CGFloat) -> Void)?
    
    var body: some View {
        VStack(spacing: 6) {
            // Top row: Icon ... Percentage
            HStack(alignment: .center) {
                // Left: Icon only (no label) - FIXED WIDTH to prevent layout jumping
                Image(systemName: hudType.icon(for: value))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(hudType == .brightness ? .yellow : .white)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolVariant(.fill)
                    .frame(width: 28, height: 22) // Fixed size prevents jumping
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hudType.icon(for: value))
                
                Spacer()
                
                // Right: Percentage with smooth number animation
                Text("\(Int(value * 100))%")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: value))
                    .animation(.spring(response: 0.2, dampingFraction: 0.8), value: value)
            }
            .padding(.horizontal, 4)
            
            // Bottom: Slider
            LiquidSlider(
                value: $value,
                accentColor: hudType == .brightness ? .yellow : .white,
                onChange: { newValue in
                    onValueChange?(newValue)
                },
                onDragChange: { newValue in
                    onValueChange?(newValue)
                }
            )
            .frame(height: 6)
            .animation(.spring(response: 0.15, dampingFraction: 0.8), value: value)
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
        .padding(.bottom, 8)
        // Ensure all elements scale together during notch expansion
        .geometryGroup()
    }
}

// MARK: - Media Player HUD

/// Compact media HUD that matches volume/brightness style
/// Album art on left, progress slider bottom, timestamp on right
struct MediaHUDView: View {
    @ObservedObject var musicManager: MusicManager
    
    /// Compute estimated position at given date
    private func estimatedPosition(at date: Date) -> Double {
        musicManager.estimatedPlaybackPosition(at: date)
    }
    
    /// Progress as percentage (0.0 - 1.0)
    private func progress(at date: Date) -> CGFloat {
        guard musicManager.songDuration > 0 else { return 0 }
        let pos = estimatedPosition(at: date)
        return CGFloat(min(1, max(0, pos / musicManager.songDuration)))
    }
    
    /// Formatted elapsed time (mm:ss)
    private func elapsedTimeString(at date: Date) -> String {
        formatTime(estimatedPosition(at: date))
    }
    
    /// Formatted remaining time (-mm:ss)
    private func remainingTimeString(at date: Date) -> String {
        let remaining = musicManager.songDuration - estimatedPosition(at: date)
        return "-\(formatTime(max(0, remaining)))"
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    var body: some View {
        // Use TimelineView for continuous updates while playing
        TimelineView(.animation(minimumInterval: 0.1, paused: !musicManager.isPlaying)) { context in
            let currentDate = context.date
            
            VStack(spacing: 6) {
                // Top row: Album Art ... Timestamp
                HStack(alignment: .center) {
                    // Left: Album Art (small, rounded)
                    Group {
                        if musicManager.albumArt.size.width > 0 {
                            Image(nsImage: musicManager.albumArt)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            // Placeholder
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.2))
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.white.opacity(0.5))
                                )
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    
                    Spacer()
                    
                    // Right: Timestamp - same font as volume percentage
                    Text(elapsedTimeString(at: currentDate))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 4)
                
                // Bottom: Progress Slider
                ProgressSlider(
                    progress: progress(at: currentDate),
                    accentColor: Color(nsColor: musicManager.avgColor)
                )
                .frame(height: 6)
            }
            .padding(.horizontal, 32)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        // Content geometry animation - all elements move together
        .geometryGroup()
    }
}

/// Progress slider that matches LiquidSlider aesthetics (non-interactive)
struct ProgressSlider: View {
    var progress: CGFloat
    var accentColor: Color
    
    private let height: CGFloat = 6
    
    /// Safe progress value - guards against NaN and infinity
    private var safeProgress: CGFloat {
        let p = progress
        if p.isNaN || p.isInfinite {
            return 0
        }
        return min(1, max(0, p))
    }
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let filledWidth = safeProgress * width
            
            ZStack(alignment: .leading) {
                // Track background - concave glass well (matches LiquidSlider)
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.05))
                    )
                    // Concave lighting: shadow on top, highlight on bottom
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    stops: [
                                        .init(color: .black.opacity(0.3), location: 0),
                                        .init(color: .clear, location: 0.3),
                                        .init(color: .white.opacity(0.2), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .frame(height: height)
                
                // Filled portion - gradient with glow (matches LiquidSlider)
                if width > 0 && safeProgress > 0 {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentColor,
                                    accentColor.opacity(0.6)
                                ],
                                startPoint: .trailing,
                                endPoint: .leading
                            )
                        )
                        .frame(width: max(height, filledWidth), height: height)
                        // Inner glow
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        stops: [
                                            .init(color: .white.opacity(0.6), location: 0),
                                            .init(color: .clear, location: 0.5)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        // Glow shadow
                        .shadow(
                            color: accentColor.opacity(0.3),
                            radius: 4,
                            x: 2,
                            y: 0
                        )
                        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: safeProgress)
                }
            }
            .frame(height: height)
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: height)
    }
}

// MARK: - Legacy HUD (kept for reference)

/// HUD overlay view that appears below the notch for volume/brightness control
/// Styled with Liquid Glass aesthetics to match Droppy's design system
struct HUDOverlayView: View {
    @Binding var isVisible: Bool
    @Binding var hudType: HUDContentType
    @Binding var value: CGFloat
    
    var onValueChange: ((CGFloat) -> Void)?
    
    @State private var animatedValue: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 14) {
            // Icon with dynamic symbol
            Image(systemName: hudType.icon(for: value))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.interpolate)
                .symbolVariant(.fill)
                .frame(width: 24, height: 20)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            
            // Slider
            LiquidSlider(
                value: $value,
                accentColor: hudType == .brightness ? .yellow : .white,
                onChange: { newValue in
                    onValueChange?(newValue)
                },
                onDragChange: { newValue in
                    onValueChange?(newValue)
                }
            )
            .frame(width: 160)
            
            // Percentage
            Text("\(Int(value * 100))%")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.gray)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(hudBackground)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.9)
        .offset(y: isVisible ? 0 : -10)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isVisible)
        .onChange(of: value) { _, newValue in
            withAnimation(.smooth(duration: 0.1)) {
                animatedValue = newValue
            }
        }
    }
    
    private var hudBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.black.opacity(0.6))
            )
            // Specular rim lighting
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.4), location: 0),
                                .init(color: .white.opacity(0.1), location: 0.3),
                                .init(color: .black.opacity(0.2), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 15, y: 8)
    }
}

// MARK: - HUD State Manager

/// Manages the HUD overlay state and auto-hide timing
@Observable
class HUDStateManager {
    static let shared = HUDStateManager()
    
    var isVisible: Bool = false
    var hudType: HUDContentType = .volume
    var value: CGFloat = 0
    
    private var hideTask: Task<Void, Never>?
    private let visibleDuration: TimeInterval = 1.5
    
    private init() {}
    
    /// Show the HUD with the given type and value
    func show(type: HUDContentType, value: CGFloat) {
        hideTask?.cancel()
        
        self.hudType = type
        self.value = value
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            self.isVisible = true
        }
        
        // Schedule auto-hide
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(visibleDuration))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                self.isVisible = false
            }
        }
    }
    
    /// Hide the HUD immediately
    func hide() {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isVisible = false
        }
    }
    
    /// Update value while HUD is visible (resets auto-hide timer)
    func updateValue(_ newValue: CGFloat) {
        value = newValue
        // Reset auto-hide timer
        show(type: hudType, value: newValue)
    }
}

// MARK: - Preview

#Preview("Notch HUD") {
    ZStack {
        Color.gray.opacity(0.3)
        
        VStack {
            // Simulate notch background
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black)
                .frame(width: 280, height: 90)
                .overlay {
                    NotchHUDView(
                        hudType: .constant(.volume),
                        value: .constant(0.65)
                    )
                }
            
            Spacer().frame(height: 40)
            
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black)
                .frame(width: 280, height: 90)
                .overlay {
                    NotchHUDView(
                        hudType: .constant(.brightness),
                        value: .constant(0.4)
                    )
                }
        }
    }
    .frame(width: 400, height: 300)
}
