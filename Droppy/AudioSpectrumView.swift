//
//  AudioSpectrumView.swift
//  Droppy
//
//  Audio visualizer for Droppy
//  Uses CAShapeLayer with random scale animations
//  Supports dynamic color from album art
//

import AppKit
import SwiftUI

// MARK: - AudioSpectrum NSView

/// Native audio spectrum visualizer using CAShapeLayer animations
/// Supports real audio levels from SystemAudioAnalyzer or enhanced simulation fallback
class AudioSpectrum: NSView {
    private var barLayers: [CAShapeLayer] = []
    private var barScales: [CGFloat] = []
    private var isPlaying: Bool = false
    private var animationTimer: Timer?
    private var currentColor: NSColor = .white
    private var secondaryColor: NSColor? = nil  // For gradient mode
    private var isGradientMode: Bool = false    // Horizontal gradient across bars
    
    // Audio-reactive pattern generation
    private var trackProgress: CGFloat = 0.5 // 0.0-1.0 track position
    private var wavePhase: CGFloat = 0 // Creates wave-like motion across bars
    private var externalAudioLevel: CGFloat? // Real audio level from SystemAudioAnalyzer
    
    private let barCount: Int
    private let barWidth: CGFloat
    private let spacing: CGFloat
    private let totalHeight: CGFloat
    private let pausedBarScale: CGFloat = 0.2
    
    init(barCount: Int = 5, barWidth: CGFloat = 3, spacing: CGFloat = 2, height: CGFloat = 14, color: NSColor = .white) {
        self.barCount = barCount
        self.barWidth = barWidth
        self.spacing = spacing
        self.totalHeight = height
        self.currentColor = color
        
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        super.init(frame: NSRect(x: 0, y: 0, width: totalWidth, height: height))
        
        wantsLayer = true
        setupBars()
    }
    
    required init?(coder: NSCoder) {
        self.barCount = 5
        self.barWidth = 3
        self.spacing = 2
        self.totalHeight = 14
        super.init(coder: coder)
        wantsLayer = true
        setupBars()
    }
    
    private func setupBars() {
        let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        frame.size = CGSize(width: totalWidth, height: totalHeight)
        
        for i in 0..<barCount {
            let xPosition = CGFloat(i) * (barWidth + spacing)
            let barLayer = CAShapeLayer()
            barLayer.frame = CGRect(x: xPosition, y: 0, width: barWidth, height: totalHeight)
            barLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            barLayer.position = CGPoint(x: xPosition + barWidth / 2, y: totalHeight / 2)
            barLayer.allowsGroupOpacity = false
            barLayer.masksToBounds = true
            
            // PREMIUM: Fully rounded pill-shaped bars
            // cornerRadius = full barWidth for maximum rounded ends
            barLayer.cornerRadius = barWidth
            
            // PREMIUM: Gradient layer (vertical or horizontal depending on mode)
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = CGRect(x: 0, y: 0, width: barWidth, height: totalHeight)
            gradientLayer.colors = [
                currentColor.withAlphaComponent(0.5).cgColor,  // Top: lighter
                currentColor.withAlphaComponent(1.0).cgColor   // Bottom: full opacity
            ]
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
            gradientLayer.cornerRadius = barWidth
            gradientLayer.name = "barGradient"  // Tag for finding later
            barLayer.addSublayer(gradientLayer)

            // Ensure a newly-mounted paused visualizer never renders at full-height bars.
            barLayer.transform = CATransform3DMakeScale(1, pausedBarScale, 1)
            
            barLayers.append(barLayer)
            barScales.append(pausedBarScale)
            layer?.addSublayer(barLayer)
        }
    }
    
    private func startAnimating() {
        guard animationTimer == nil else { return }
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateBars()
        }
        // Trigger immediate update
        updateBars()
    }
    
    private func stopAnimating() {
        animationTimer?.invalidate()
        animationTimer = nil
        resetBars()
    }
    
    override func removeFromSuperview() {
        stopAnimating()
        super.removeFromSuperview()
    }
    
    private func updateBars() {
        // Advance wave phase for organic motion (simulation mode only)
        wavePhase += 0.3
        if wavePhase > 2 * .pi { wavePhase -= 2 * .pi }
        
        for (i, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[i]
            let targetScale: CGFloat
            
            if let audioLevel = externalAudioLevel {
                // REAL AUDIO MODE: iPhone-like reactive bars (v21.69 refinement)
                // Each bar gets independent variation for natural look
                let barVariation = CGFloat.random(in: -0.15...0.15)
                
                // Apply logarithmic scaling to make bars less sensitive
                // This prevents them from hitting 100% too quickly
                // Minimum 0.12 (small bars when quiet), max 0.85 (never fully maxed)
                let logLevel = log10(1 + audioLevel * 9) / log10(10)  // Logarithmic curve
                let baseScale = 0.12 + (logLevel * 0.55)  // Max ~0.67 before variation
                targetScale = max(0.12, min(0.85, baseScale + barVariation))
            } else {
                // SIMULATION MODE: Enhanced wave patterns with track progress
                let energyMultiplier: CGFloat
                let baseMin: CGFloat
                let baseMax: CGFloat
                
                if trackProgress < 0.2 {
                    let introProgress = trackProgress / 0.2
                    energyMultiplier = 0.6 + (introProgress * 0.4)
                    baseMin = 0.3
                    baseMax = 0.7 + (introProgress * 0.3)
                } else if trackProgress > 0.8 {
                    let outroProgress = 1.0 - ((trackProgress - 0.8) / 0.2)
                    energyMultiplier = 0.6 + (outroProgress * 0.4)
                    baseMin = 0.3
                    baseMax = 0.7 + (outroProgress * 0.3)
                } else {
                    energyMultiplier = 1.0
                    baseMin = 0.35
                    baseMax = 1.0
                }
                
                let barPhase = wavePhase + (CGFloat(i) * 0.4)
                let waveInfluence = (sin(barPhase) + 1) / 2 * 0.3
                let randomComponent = CGFloat.random(in: baseMin...baseMax)
                targetScale = max(0.25, min(1.0, (randomComponent * 0.7 + waveInfluence) * energyMultiplier))
            }
            
            barScales[i] = targetScale
            
            if externalAudioLevel != nil {
                // REAL AUDIO: Spring animation for smooth, natural motion
                let spring = CASpringAnimation(keyPath: "transform.scale.y")
                spring.fromValue = currentScale
                spring.toValue = targetScale
                spring.damping = 12 // Higher = less bounce
                spring.stiffness = 300 // Higher = faster response
                spring.mass = 0.8
                spring.initialVelocity = 0
                spring.duration = spring.settlingDuration
                spring.fillMode = .forwards
                spring.isRemovedOnCompletion = false
                
                // PERFORMANCE: Cap at 60fps - 120fps isn't needed for small bar animations
                if #available(macOS 13.0, *) {
                    spring.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                }
                
                barLayer.add(spring, forKey: "scaleY")
            } else {
                // SIMULATION: Basic animation with easeOut
                let animation = CABasicAnimation(keyPath: "transform.scale.y")
                animation.fromValue = currentScale
                animation.toValue = targetScale
                animation.duration = 0.3
                // PERFORMANCE: Removed autoreverses - was causing double animation work
                animation.fillMode = .forwards
                animation.isRemovedOnCompletion = false
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                
                // PERFORMANCE: Cap at 60fps - 120fps isn't needed for small bar animations
                if #available(macOS 13.0, *) {
                    animation.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                }
                
                barLayer.add(animation, forKey: "scaleY")
            }
        }
    }
    
    private func resetBars() {
        // Animate bars smoothly back to small/paused state
        for (i, barLayer) in barLayers.enumerated() {
            let currentScale = barScales[i]
            let targetScale = pausedBarScale // Small bars when paused
            
            barScales[i] = targetScale
            
            // Smooth spring animation to paused state
            let spring = CASpringAnimation(keyPath: "transform.scale.y")
            spring.fromValue = currentScale
            spring.toValue = targetScale
            spring.damping = 15
            spring.stiffness = 200
            spring.mass = 0.6
            spring.duration = spring.settlingDuration
            spring.fillMode = .forwards
            spring.isRemovedOnCompletion = false
            
            barLayer.add(spring, forKey: "scaleY")
        }
    }
    
    func setPlaying(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
        if isPlaying {
            startAnimating()
        } else {
            stopAnimating()
        }
    }
    
    func setColor(_ color: NSColor) {
        guard currentColor != color else { return }
        currentColor = color
        updateBarColors()
    }
    
    /// Set secondary color for gradient mode (horizontal gradient across bars)
    func setSecondaryColor(_ color: NSColor?) {
        secondaryColor = color
        if isGradientMode {
            updateBarColors()
        }
    }
    
    /// Enable/disable gradient mode (horizontal gradient from primary to secondary color)
    func setGradientMode(_ enabled: Bool) {
        guard isGradientMode != enabled else { return }
        isGradientMode = enabled
        updateBarColors()
    }
    
    /// Update all bar gradient colors based on current mode
    private func updateBarColors() {
        for (_, barLayer) in barLayers.enumerated() {
            guard let gradientLayer = barLayer.sublayers?.first(where: { $0.name == "barGradient" }) as? CAGradientLayer else { continue }
            
            if isGradientMode, let secondary = secondaryColor {
                // GRADIENT MODE: Vertical gradient from bottom (primary) to top (secondary)
                // Boost saturation for more vibrant colors
                let boostedPrimary = boostSaturation(currentColor, amount: 1.3)
                let boostedSecondary = boostSaturation(secondary, amount: 1.3)
                
                gradientLayer.colors = [
                    boostedSecondary.withAlphaComponent(0.7).cgColor,  // Top: secondary color (lighter)
                    boostedPrimary.withAlphaComponent(1.0).cgColor     // Bottom: primary color (full)
                ]
                // Vertical gradient: top to bottom
                gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
                gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
            } else {
                // SINGLE COLOR MODE: Standard vertical gradient (lighter at top)
                gradientLayer.colors = [
                    currentColor.withAlphaComponent(0.5).cgColor,  // Top: lighter
                    currentColor.withAlphaComponent(1.0).cgColor   // Bottom: full opacity
                ]
                gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
                gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
            }
        }
    }
    
    /// Boost saturation of a color for more vibrant gradients
    private func boostSaturation(_ color: NSColor, amount: CGFloat) -> NSColor {
        guard let hsbColor = color.usingColorSpace(.deviceRGB) else { return color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        hsbColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(1.0, saturation * amount), brightness: brightness, alpha: alpha)
    }
    
    /// Blend two NSColors based on progress (0.0 = first color, 1.0 = second color)
    private func blendColors(_ color1: NSColor, _ color2: NSColor, progress: CGFloat) -> NSColor {
        let c1 = color1.usingColorSpace(.deviceRGB) ?? color1
        let c2 = color2.usingColorSpace(.deviceRGB) ?? color2
        
        let r = c1.redComponent + (c2.redComponent - c1.redComponent) * progress
        let g = c1.greenComponent + (c2.greenComponent - c1.greenComponent) * progress
        let b = c1.blueComponent + (c2.blueComponent - c1.blueComponent) * progress
        let a = c1.alphaComponent + (c2.alphaComponent - c1.alphaComponent) * progress
        
        return NSColor(red: r, green: g, blue: b, alpha: a)
    }
    
    /// Update track progress for pattern variation (simulation mode)
    func setTrackProgress(_ progress: CGFloat) {
        trackProgress = max(0, min(1, progress))
    }
    
    /// Set external audio level from SystemAudioAnalyzer (real audio mode)
    /// Pass nil to use simulation mode
    func setAudioLevel(_ level: CGFloat?) {
        externalAudioLevel = level
    }
}

// MARK: - SwiftUI Wrapper

/// SwiftUI wrapper for AudioSpectrum (supports real audio or simulation)
struct AudioSpectrumView: NSViewRepresentable {
    let isPlaying: Bool
    var barCount: Int = 5
    var barWidth: CGFloat = 3
    var spacing: CGFloat = 2
    var height: CGFloat = 14
    var color: Color = .white
    var secondaryColor: Color? = nil  // Secondary color for gradient mode
    var gradientMode: Bool = false    // Enable horizontal gradient across bars
    var trackProgress: CGFloat = 0.5 // 0.0-1.0 track position for simulation mode
    var audioLevel: CGFloat? = nil   // Real audio level (nil = use simulation)
    
    func makeNSView(context: Context) -> AudioSpectrum {
        let nsColor = NSColor(color)
        let spectrum = AudioSpectrum(barCount: barCount, barWidth: barWidth, spacing: spacing, height: height, color: nsColor)
        spectrum.setPlaying(isPlaying)
        spectrum.setSecondaryColor(secondaryColor.map { NSColor($0) })
        spectrum.setGradientMode(gradientMode)
        spectrum.setTrackProgress(trackProgress)
        spectrum.setAudioLevel(audioLevel)
        return spectrum
    }
    
    func updateNSView(_ nsView: AudioSpectrum, context: Context) {
        nsView.setPlaying(isPlaying)
        nsView.setColor(NSColor(color))
        nsView.setSecondaryColor(secondaryColor.map { NSColor($0) })
        nsView.setGradientMode(gradientMode)
        nsView.setTrackProgress(trackProgress)
        nsView.setAudioLevel(audioLevel)
    }
}

// MARK: - Color Extraction from Image

extension NSImage {
    /// Extract dominant/average color from image (brightness-enhanced for visibility)
    func dominantColor() -> Color {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return .white
        }
        
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        
        guard width > 0 && height > 0 else { return .white }
        
        var totalR: CGFloat = 0
        var totalG: CGFloat = 0
        var totalB: CGFloat = 0
        var count: CGFloat = 0
        
        // Sample a grid of pixels for efficiency
        let step = max(1, min(width, height) / 10)
        
        for x in stride(from: 0, to: width, by: step) {
            for y in stride(from: 0, to: height, by: step) {
                if let color = bitmap.colorAt(x: x, y: y) {
                    // Convert to RGB color space to safely access components
                    guard let rgbColor = color.usingColorSpace(.deviceRGB) else { continue }
                    
                    let r = rgbColor.redComponent
                    let g = rgbColor.greenComponent
                    let b = rgbColor.blueComponent
                    
                    // Weight by saturation - prefer colorful pixels
                    let maxC = max(r, g, b)
                    let minC = min(r, g, b)
                    let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
                    let weight = 0.3 + saturation * 0.7
                    
                    totalR += r * weight
                    totalG += g * weight
                    totalB += b * weight
                    count += weight
                }
            }
        }
        
        guard count > 0 else { return .white }
        
        var avgR = totalR / count
        var avgG = totalG / count
        var avgB = totalB / count
        
        // Boost brightness for visibility (target ~0.7 brightness)
        let brightness = (avgR + avgG + avgB) / 3
        if brightness < 0.5 {
            let boost = min(2.0, 0.7 / max(brightness, 0.1))
            avgR = min(1.0, avgR * boost)
            avgG = min(1.0, avgG * boost)
            avgB = min(1.0, avgB * boost)
        }
        
        return Color(red: avgR, green: avgG, blue: avgB)
    }
    
    /// Extract two visually distinct colors from image for gradient visualizer
    /// Returns (primary, secondary) colors from different regions of the image
    /// If colors are too similar, applies hue shift to secondary for visible gradient
    func extractTwoColors() -> (primary: Color, secondary: Color) {
        guard let tiffData = self.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return (.white, .gray)
        }
        
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        
        guard width > 0 && height > 0 else { return (.white, .gray) }
        
        // Sample left half for primary color, right half for secondary
        let step = max(1, min(width, height) / 10)
        
        var leftR: CGFloat = 0, leftG: CGFloat = 0, leftB: CGFloat = 0, leftCount: CGFloat = 0
        var rightR: CGFloat = 0, rightG: CGFloat = 0, rightB: CGFloat = 0, rightCount: CGFloat = 0
        
        for x in stride(from: 0, to: width, by: step) {
            for y in stride(from: 0, to: height, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y),
                      let rgbColor = color.usingColorSpace(.deviceRGB) else { continue }
                
                let r = rgbColor.redComponent
                let g = rgbColor.greenComponent
                let b = rgbColor.blueComponent
                
                // Weight by saturation - prefer colorful pixels
                let maxC = max(r, g, b)
                let minC = min(r, g, b)
                let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
                let weight = 0.3 + saturation * 0.7
                
                if x < width / 2 {
                    leftR += r * weight
                    leftG += g * weight
                    leftB += b * weight
                    leftCount += weight
                } else {
                    rightR += r * weight
                    rightG += g * weight
                    rightB += b * weight
                    rightCount += weight
                }
            }
        }
        
        func boostBrightness(_ r: inout CGFloat, _ g: inout CGFloat, _ b: inout CGFloat) {
            let brightness = (r + g + b) / 3
            if brightness < 0.5 {
                let boost = min(2.0, 0.7 / max(brightness, 0.1))
                r = min(1.0, r * boost)
                g = min(1.0, g * boost)
                b = min(1.0, b * boost)
            }
        }
        
        var avgLeftR = leftCount > 0 ? leftR / leftCount : 1.0
        var avgLeftG = leftCount > 0 ? leftG / leftCount : 1.0
        var avgLeftB = leftCount > 0 ? leftB / leftCount : 1.0
        boostBrightness(&avgLeftR, &avgLeftG, &avgLeftB)
        
        var avgRightR = rightCount > 0 ? rightR / rightCount : 0.5
        var avgRightG = rightCount > 0 ? rightG / rightCount : 0.5
        var avgRightB = rightCount > 0 ? rightB / rightCount : 0.5
        boostBrightness(&avgRightR, &avgRightG, &avgRightB)
        
        let primaryColor = Color(red: avgLeftR, green: avgLeftG, blue: avgLeftB)
        var secondaryColor = Color(red: avgRightR, green: avgRightG, blue: avgRightB)
        
        // Check if colors are too similar - if so, apply hue shift to secondary
        let colorDiff = abs(avgLeftR - avgRightR) + abs(avgLeftG - avgRightG) + abs(avgLeftB - avgRightB)
        if colorDiff < 0.3 {
            // Colors are too similar - apply 60° hue rotation to secondary for visible gradient
            let nsColor = NSColor(red: avgRightR, green: avgRightG, blue: avgRightB, alpha: 1.0)
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
            nsColor.usingColorSpace(.deviceRGB)?.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            
            // Shift hue by ~60° and boost saturation for visible difference
            let newHue = (hue + 0.167).truncatingRemainder(dividingBy: 1.0)
            let newSat = min(1.0, max(0.4, sat * 1.3))  // Ensure minimum saturation
            secondaryColor = Color(hue: Double(newHue), saturation: Double(newSat), brightness: Double(bri))
        }
        
        return (primaryColor, secondaryColor)
    }
}

#Preview {
    AudioSpectrumView(isPlaying: true, color: .blue)
        .frame(width: 25, height: 20)
        .padding()
        .background(Color.black)
}
