//
//  LockScreenMediaPanelView.swift
//  Droppy
//
//  Created by Droppy on 26/01/2026.
//  SwiftUI view for the lock screen media widget
//  Displays album art, track info, progress bar, visualizer and playback controls
//

import SwiftUI
import AppKit
import ObjectiveC.runtime

/// Lock screen media panel - iPhone-inspired design
/// Displays on the macOS lock screen via SkyLight.framework
struct LockScreenMediaPanelView: View {
    @EnvironmentObject var musicManager: MusicManager
    @ObservedObject var animator: LockScreenMediaPanelAnimator
    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground
    @AppStorage(AppPreferenceKey.lockScreenMediaLiquidGlassVariant) private var lockScreenMediaLiquidGlassVariant = PreferenceDefault.lockScreenMediaLiquidGlassVariant
    @State private var spotifyController = SpotifyController.shared
    @State private var appleMusicController = AppleMusicController.shared
    
    // MARK: - Layout Constants (pixel-perfect, synced with Manager)
    private let panelWidth: CGFloat = 380
    private let panelHeight: CGFloat = 160
    private let cornerRadius: CGFloat = 24
    private let edgePadding: CGFloat = 16
    private let albumArtSize: CGFloat = 56
    private let albumArtRadius: CGFloat = 10
    
    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var clampedLiquidGlassVariant: Int {
        min(max(lockScreenMediaLiquidGlassVariant, 0), 19)
    }
    
    // MARK: - Body
    
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let estimatedTime = musicManager.estimatedPlaybackPosition(at: context.date)
            let progress: Double = musicManager.songDuration > 0 
                ? min(1, max(0, estimatedTime / musicManager.songDuration)) 
                : 0
            let glassTrigger = context.date.timeIntervalSinceReferenceDate
            
            VStack(spacing: 14) {
                // Row 1: Album Art + Track Info + Visualizer
                HStack(alignment: .center, spacing: 0) {
                    // Album art
                    albumArtView
                        .padding(.trailing, 12)
                    
                    // Track info (title + artist)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(musicManager.songTitle.isEmpty ? "Not Playing" : musicManager.songTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(musicManager.artistName.isEmpty ? "Unknown Artist" : musicManager.artistName)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    
                    Spacer(minLength: 0)
                    
                    // Visualizer (5 bars) - at exact right edge
                    AudioSpectrumView(
                        isPlaying: musicManager.isPlaying,
                        barCount: 5,
                        barWidth: 3,
                        spacing: 2,
                        height: 20,
                        color: musicManager.visualizerColor
                    )
                    .frame(width: 23, height: 20) // Explicit frame for visualizer (5*3 + 4*2 = 23)
                }
                // CRITICAL: Explicitly set frame width to ensure Spacer() works
                // width = panelWidth (380) - padding (16*2=32) = 348
                .frame(width: panelWidth - (edgePadding * 2), height: albumArtSize)
                
                // Row 2: Progress bar with timestamps
                HStack(spacing: 8) {
                    Text(formatTime(estimatedTime))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 32, alignment: .leading)
                    
                    // Progress track
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Background track
                            Capsule()
                                .fill(AdaptiveColors.overlayAuto(0.2))
                            
                            // Progress fill
                            Capsule()
                                .fill(AdaptiveColors.overlayAuto(0.9))
                                .frame(width: max(0, geo.size.width * progress))
                        }
                    }
                    .frame(height: 4)
                    
                    Text(formatTime(musicManager.songDuration))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 32, alignment: .trailing)
                }
                
                // Row 3: Media controls (centered)
                controlsRow
            }
            .padding(edgePadding)
            .frame(width: panelWidth, height: panelHeight)
            .background(panelBackground(glassTrigger: glassTrigger))
            .clipShape(panelShape)
            .overlay(panelBorderOverlay)
            .shadow(
                color: useTransparentBackground ? .clear : Color.black.opacity(0.4),
                radius: useTransparentBackground ? 0 : 30,
                x: 0,
                y: useTransparentBackground ? 0 : 15
            )
            // Entry/exit animations - FAST
            .scaleEffect(animator.isPresented ? 1 : 0.9, anchor: .center)
            .opacity(animator.isPresented ? 1 : 0)
            .animation(DroppyAnimation.hoverQuick, value: animator.isPresented)
        }
        .onAppear(perform: refreshProviderStateIfNeeded)
        .onChange(of: musicManager.bundleIdentifier) { _, _ in
            refreshProviderStateIfNeeded()
        }
    }
    
    // MARK: - Panel Background
    
    @ViewBuilder
    private func panelBackground(glassTrigger: TimeInterval) -> some View {
        if useTransparentBackground {
            // Use the same live-resampling glass strategy as live lock-screen glass surfaces.
            if #available(macOS 26.0, *) {
                LockScreenLiveLiquidGlassBackground(
                    cornerRadius: cornerRadius,
                    trigger: glassTrigger,
                    variantRawValue: clampedLiquidGlassVariant
                ) {
                    Color.white.opacity(0.04)
                }
            } else {
                panelShape
                    .fill(.ultraThinMaterial)
            }
        } else {
            // Dark solid
            panelShape
                .fill(Color.black.opacity(0.85))
        }
    }
    
    @ViewBuilder
    private var panelBorderOverlay: some View {
        if useTransparentBackground {
            if #unavailable(macOS 26.0) {
                panelShape
                    .stroke(AdaptiveColors.overlayAuto(0.2), lineWidth: 1)
            }
        } else {
            panelShape
                .stroke(AdaptiveColors.overlayAuto(0.1), lineWidth: 1)
        }
    }
    
    // MARK: - Controls
    
    @ViewBuilder
    private var controlsRow: some View {
        let isSpotify = musicManager.isSpotifySource
        let isAppleMusic = musicManager.isAppleMusicSource
        let spotifyGreen = Color(red: 0.11, green: 0.73, blue: 0.33)
        let appleMusicPink = Color(red: 0.98, green: 0.34, blue: 0.40)
        
        HStack(spacing: 14) {
            if isSpotify {
                SpotifyControlButton(
                    icon: "shuffle",
                    isActive: spotifyController.shuffleEnabled,
                    accentColor: spotifyGreen,
                    size: 14
                ) {
                    spotifyController.toggleShuffle()
                }
            } else if isAppleMusic {
                SpotifyControlButton(
                    icon: "shuffle",
                    isActive: appleMusicController.shuffleEnabled,
                    accentColor: appleMusicPink,
                    size: 14
                ) {
                    appleMusicController.toggleShuffle()
                }
            }
            
            MediaControlButton(
                icon: "backward.fill",
                size: 22,
                foregroundColor: .white,
                tapPadding: 6,
                nudgeDirection: .left
            ) {
                musicManager.previousTrack()
            }
            
            MediaControlButton(
                icon: musicManager.isPlaying ? "pause.fill" : "play.fill",
                size: 26,
                foregroundColor: .white,
                tapPadding: 6
            ) {
                musicManager.togglePlay()
            }
            
            MediaControlButton(
                icon: "forward.fill",
                size: 22,
                foregroundColor: .white,
                tapPadding: 6,
                nudgeDirection: .right
            ) {
                musicManager.nextTrack()
            }
            
            if isSpotify {
                SpotifyControlButton(
                    icon: spotifyController.repeatMode.iconName,
                    isActive: spotifyController.repeatMode != .off,
                    accentColor: spotifyGreen,
                    size: 14
                ) {
                    spotifyController.cycleRepeatMode()
                }
            } else if isAppleMusic {
                SpotifyControlButton(
                    icon: appleMusicController.repeatMode.iconName,
                    isActive: appleMusicController.repeatMode != .off,
                    accentColor: appleMusicPink,
                    size: 14
                ) {
                    appleMusicController.cycleRepeatMode()
                }
            }
            
            if isAppleMusic {
                SpotifyControlButton(
                    icon: appleMusicController.isCurrentTrackLoved ? "heart.fill" : "heart",
                    isActive: appleMusicController.isCurrentTrackLoved,
                    isLoading: appleMusicController.isLoveLoading,
                    accentColor: appleMusicPink,
                    size: 14
                ) {
                    appleMusicController.toggleLove()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    // MARK: - Album Art
    
    @ViewBuilder
    private var albumArtView: some View {
        if musicManager.albumArt.size.width > 0 {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: albumArtSize, height: albumArtSize)
                .clipShape(RoundedRectangle(cornerRadius: albumArtRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: albumArtRadius, style: .continuous)
                .fill(AdaptiveColors.overlayAuto(0.1))
                .frame(width: albumArtSize, height: albumArtSize)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                )
        }
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    private func refreshProviderStateIfNeeded() {
        if musicManager.isSpotifySource {
            spotifyController.refreshState()
        } else if musicManager.isAppleMusicSource {
            appleMusicController.refreshState()
        }
    }
}

// MARK: - Native Live Liquid Glass (live glass parity)

private struct LockScreenLiveLiquidGlassBackground<Content: View>: NSViewRepresentable {
    private let cornerRadius: CGFloat
    private let trigger: TimeInterval
    private let variantRawValue: Int
    private let content: Content

    init(cornerRadius: CGFloat, trigger: TimeInterval, variantRawValue: Int, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.trigger = trigger
        self.variantRawValue = min(max(variantRawValue, 0), 19)
        self.content = content()
    }

    func makeNSView(context: Context) -> NSView {
        if let glassType = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassType.init(frame: .zero)
            applyCornerRadiusIfSupported(on: glass)
            callPrivateVariantSetter(on: glass, value: variantRawValue)

            let hosting = NSHostingView(rootView: content)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            glass.setValue(hosting, forKey: "contentView")
            return glass
        }

        let fallback = NSVisualEffectView()
        fallback.material = .underWindowBackground
        fallback.state = .active
        fallback.blendingMode = .behindWindow

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        fallback.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: fallback.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: fallback.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: fallback.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: fallback.bottomAnchor)
        ])
        return fallback
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let hosting = nsView.value(forKey: "contentView") as? NSHostingView<Content> {
            hosting.rootView = content
        } else if let hosting = nsView.subviews.compactMap({ $0 as? NSHostingView<Content> }).first {
            hosting.rootView = content
        }

        applyCornerRadiusIfSupported(on: nsView)
        callPrivateVariantSetter(on: nsView, value: variantRawValue)

        // Micro-jitter forces WindowServer backdrop resampling so animated wallpapers stay live.
        let jitter = sin(trigger * 100) * 0.000001
        nsView.alphaValue = 1.0 - CGFloat(abs(jitter))
        nsView.needsDisplay = true
    }

    private func callPrivateVariantSetter(on object: AnyObject, value: Int) {
        let selector = NSSelectorFromString("set_variant:")
        guard
            let method = class_getInstanceMethod(object_getClass(object), selector)
        else { return }

        typealias SetterIMP = @convention(c) (AnyObject, Selector, Int) -> Void
        let implementation = method_getImplementation(method)
        let function = unsafeBitCast(implementation, to: SetterIMP.self)
        function(object, selector, value)
    }

    private func applyCornerRadiusIfSupported(on object: AnyObject) {
        let selector = NSSelectorFromString("setCornerRadius:")
        guard class_getInstanceMethod(object_getClass(object), selector) != nil else { return }
        object.setValue(cornerRadius, forKey: "cornerRadius")
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.blue.opacity(0.6)
        LockScreenMediaPanelView(animator: LockScreenMediaPanelAnimator())
            .environmentObject(MusicManager.shared)
    }
    .frame(width: 500, height: 300)
}
