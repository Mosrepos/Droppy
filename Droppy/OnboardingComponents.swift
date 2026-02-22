import SwiftUI

// MARK: - Onboarding Components
// Extracted from OnboardingView.swift for faster incremental builds

struct OnboardingToggle: View {
    let icon: String
    let title: String
    let color: Color
    @Binding var isOn: Bool
    var secondaryColor: Color? = nil
    
    @State private var iconBounce = false
    @State private var isHovering = false
    
    private var gradientSecondaryColor: Color {
        secondaryColor ?? color.opacity(0.7)
    }
    
    var body: some View {
        Button {
            // Trigger icon bounce
            withAnimation(DroppyAnimation.onboardingPop) {
                iconBounce = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(DroppyAnimation.stateEmphasis) {
                    iconBounce = false
                    isOn.toggle()
                }
            }
        } label: {
            HStack(spacing: 12) {
                // Premium gradient squircle icon
                ZStack {
                    RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [color, gradientSecondaryColor],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    // Inner highlight for 3D effect
                    RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [AdaptiveColors.overlayAuto(0.25), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .droppyTextShadow()
                        .scaleEffect(iconBounce ? 1.3 : 1.0)
                        .rotationEffect(.degrees(iconBounce ? -8 : 0))
                }
                
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isOn ? .primary : .secondary)
                
                Spacer()
                
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isOn ? .green : .secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(AdaptiveColors.buttonBackgroundAuto)
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                    .stroke(isOn ? color.opacity(0.3) : AdaptiveColors.overlayAuto(0.08), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
        }
        .buttonStyle(DroppySelectableButtonStyle(isSelected: isOn))
        .onHover { hovering in
            withAnimation(DroppyAnimation.hover) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Onboarding View


struct OnboardingConfettiView: View {
    @State private var particles: [OnboardingParticle] = []
    @State private var isVisible = true
    
    var body: some View {
        GeometryReader { geo in
            if isVisible {
                Canvas { context, size in
                    for particle in particles {
                        let rect = CGRect(
                            x: particle.currentX - particle.size / 2,
                            y: particle.currentY - particle.size * 0.75,
                            width: particle.size,
                            height: particle.size * 1.5
                        )
                        context.fill(
                            RoundedRectangle(cornerRadius: 1).path(in: rect),
                            with: .color(particle.color.opacity(particle.opacity))
                        )
                    }
                }
                .onAppear {
                    createParticles(in: geo.size)
                    startAnimation()
                }
            }
        }
    }
    
    private func createParticles(in size: CGSize) {
        let colors: [Color] = [.blue, .green, .yellow, .orange, .pink, .purple, .cyan]
        
        for i in 0..<24 {
            var particle = OnboardingParticle(
                id: i,
                x: CGFloat.random(in: 40...(size.width - 40)),
                startY: size.height + 10,
                endY: CGFloat.random(in: -20...size.height * 0.3),
                color: colors[i % colors.count],
                size: CGFloat.random(in: 5...8),
                delay: Double(i) * 0.015
            )
            particle.currentX = particle.x
            particle.currentY = particle.startY
            particles.append(particle)
        }
    }
    
    private func startAnimation() {
        for i in 0..<particles.count {
            let delay = particles[i].delay
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard i < particles.count else { return }
                withAnimation(.easeOut(duration: 1.2)) {
                    particles[i].currentY = particles[i].endY
                    particles[i].currentX = particles[i].x + CGFloat.random(in: -30...30)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.9) {
                guard i < particles.count else { return }
                withAnimation(.easeIn(duration: 0.3)) {
                    particles[i].opacity = 0
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            isVisible = false
        }
    }
}

struct OnboardingParticle: Identifiable {
    let id: Int
    let x: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let color: Color
    let size: CGFloat
    let delay: Double
    var currentX: CGFloat = 0
    var currentY: CGFloat = 0
    var opacity: Double = 1
}

// MARK: - Window Controller

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    enum ActivationMode {
        case forceForeground
        case onlyIfAlreadyActive
    }
    
    private var window: NSWindow?
    private var isClosing = false
    private var deferredTeardownWorkItem: DispatchWorkItem?
    private let deferredTeardownDelay: TimeInterval = 8
    
    private override init() {
        super.init()
    }
    
    func show(activationMode: ActivationMode = .forceForeground) {
        guard shouldPresentWindow(for: activationMode) else { return }
        cancelDeferredTeardown()

        // If window exists, warm-reopen it.
        if let existingWindow = window {
            if existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                activateIfAllowed(for: activationMode)
                return
            } else {
                AppKitMotion.prepareForPresent(existingWindow, initialScale: 1.0)
                existingWindow.orderFront(nil)
                DispatchQueue.main.async {
                    self.activateIfAllowed(for: activationMode)
                    existingWindow.makeKeyAndOrderFront(nil)
                }
                AppKitMotion.animateIn(existingWindow, initialScale: 1.0, duration: 0.2)
                return
            }
        }
        
        let contentView = OnboardingView(
            onComplete: { [weak self] in
                // Defer to next runloop to avoid releasing view while callback is in progress
                DispatchQueue.main.async {
                    // Mark onboarding as complete first
                    UserDefaults.standard.set(true, forKey: AppPreferenceKey.hasCompletedOnboarding)
                    self?.close()
                }
            },
            onPageChange: { [weak self] page in
                self?.resizeWindow(for: page, animated: true)
            }
        )

        
        let hostingView = NSHostingView(rootView: contentView)
        
        // Use NSPanel with borderless style to match extension windows (no traffic lights)
        let newWindow = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: OnboardingView.standardWindowSize.width,
                height: OnboardingView.standardWindowSize.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.title = "Welcome to Droppy"
        newWindow.backgroundColor = .clear  // Clear to allow SwiftUI Liquid mode
        newWindow.isOpaque = false
        newWindow.hasShadow = true
        newWindow.isMovableByWindowBackground = true
        newWindow.isReleasedWhenClosed = false  // Prevent premature deallocation
        newWindow.delegate = self  // Handle window close
        newWindow.contentView = hostingView
        
        // Precisely center on the main screen (MacBook's built-in display)
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = newWindow.frame
            let x = screenFrame.midX - windowFrame.width / 2
            let y = screenFrame.midY - windowFrame.height / 2
            newWindow.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            newWindow.center()
        }
        newWindow.level = .floating
        
        // Store reference AFTER setup
        window = newWindow

        AppKitMotion.prepareForPresent(newWindow, initialScale: 1.0)
        newWindow.orderFront(nil)
        DispatchQueue.main.async {
            self.activateIfAllowed(for: activationMode)
            newWindow.makeKeyAndOrderFront(nil)
        }
        AppKitMotion.animateIn(newWindow, initialScale: 1.0, duration: 0.2)
    }
    
    func close() {
        guard let panel = window, !isClosing else { return }
        isClosing = true

        AppKitMotion.animateOut(panel, targetScale: 1.0, duration: 0.15) { [weak self] in
            guard let self else { return }
            panel.orderOut(nil)
            AppKitMotion.resetPresentationState(panel)
            self.isClosing = false
            self.scheduleDeferredTeardown()
        }
    }

    private func scheduleDeferredTeardown() {
        deferredTeardownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.window, !panel.isVisible else { return }
            panel.contentView = nil
            panel.delegate = nil
            self.window = nil
            self.deferredTeardownWorkItem = nil
        }
        deferredTeardownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + deferredTeardownDelay, execute: workItem)
    }

    private func cancelDeferredTeardown() {
        deferredTeardownWorkItem?.cancel()
        deferredTeardownWorkItem = nil
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // Clear reference when window is closed via X button
        window = nil
        isClosing = false
        cancelDeferredTeardown()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        close()
        return false
    }

    private func shouldPresentWindow(for activationMode: ActivationMode) -> Bool {
        switch activationMode {
        case .forceForeground:
            return true
        case .onlyIfAlreadyActive:
            return isDroppyFrontmostAndActive
        }
    }

    private func activateIfAllowed(for activationMode: ActivationMode) {
        switch activationMode {
        case .forceForeground:
            NSApp.activate(ignoringOtherApps: true)
        case .onlyIfAlreadyActive:
            guard isDroppyFrontmostAndActive else { return }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private var isDroppyFrontmostAndActive: Bool {
        guard NSApp.isActive else { return false }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return false }
        return frontmost.processIdentifier == ProcessInfo.processInfo.processIdentifier
    }

    private func resizeWindow(for page: OnboardingPage, animated: Bool) {
        guard let window else { return }
        let targetSize = OnboardingView.windowSize(for: page)

        // Avoid redundant frame animations
        guard abs(window.frame.width - targetSize.width) > 0.5 || abs(window.frame.height - targetSize.height) > 0.5 else {
            return
        }

        var newFrame = window.frame
        let heightDelta = targetSize.height - newFrame.height
        newFrame.size = targetSize
        newFrame.origin.y -= heightDelta / 2  // keep center visually stable

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }
}
