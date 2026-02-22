import AppKit
import QuartzCore

private final class MotionCompletionBox: @unchecked Sendable {
    let completion: (() -> Void)?

    init(_ completion: (() -> Void)?) {
        self.completion = completion
    }
}

@MainActor
enum AppKitMotion {
    private static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private static let openTiming = CAMediaTimingFunction(name: .easeOut)
    private static let closeTiming = CAMediaTimingFunction(name: .easeIn)

    @discardableResult
    private static func ensureLayer(on view: NSView?) -> CALayer? {
        guard let view else { return nil }
        if !view.wantsLayer {
            view.wantsLayer = true
        }
        view.layerContentsRedrawPolicy = .onSetNeedsDisplay

        guard let layer = view.layer else { return nil }

        let noAction = NSNull()
        layer.actions = [
            "position": noAction,
            "bounds": noAction,
            "frame": noAction,
            "transform": noAction,
            "opacity": noAction,
            "contents": noAction
        ]
        return layer
    }

    static func prepareForPresent(_ window: NSWindow, initialScale: CGFloat = 0.9) {
        _ = initialScale
        window.alphaValue = 0

        guard let layer = ensureLayer(on: window.contentView) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    static func animateIn(
        _ window: NSWindow,
        initialScale: CGFloat = 0.9,
        duration: TimeInterval = 0.2,
        completion: (() -> Void)? = nil
    ) {
        _ = initialScale
        let requestedDuration = max(duration, 0.01)
        let tunedDuration = reduceMotion ? min(requestedDuration, 0.16) : requestedDuration
        let completionBox = MotionCompletionBox(completion)

        if let layer = ensureLayer(on: window.contentView) {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = tunedDuration
            fade.timingFunction = openTiming
            layer.add(fade, forKey: "droppy.fadeIn")

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = tunedDuration
            context.timingFunction = openTiming
            window.animator().alphaValue = 1
        }, completionHandler: {
            completionBox.completion?()
        })
    }

    static func animateOut(
        _ window: NSWindow,
        targetScale: CGFloat = 0.96,
        duration: TimeInterval = 0.15,
        completion: (() -> Void)? = nil
    ) {
        _ = targetScale
        let requestedDuration = max(duration, 0.01)
        let tunedDuration = reduceMotion ? min(requestedDuration, 0.14) : requestedDuration
        let completionBox = MotionCompletionBox(completion)

        if let layer = ensureLayer(on: window.contentView) {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = tunedDuration
            fade.timingFunction = closeTiming
            layer.add(fade, forKey: "droppy.fadeOut")

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 0
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = tunedDuration
            context.timingFunction = closeTiming
            window.animator().alphaValue = 0
        }, completionHandler: {
            completionBox.completion?()
        })
    }

    static func resetPresentationState(_ window: NSWindow) {
        window.alphaValue = 1
        guard let layer = ensureLayer(on: window.contentView) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    static func animateFrame(_ window: NSWindow, to frame: NSRect, duration: TimeInterval = 0.22) {
        if reduceMotion {
            window.setFrame(frame, display: true, animate: false)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = openTiming
            context.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
        }
    }
}
