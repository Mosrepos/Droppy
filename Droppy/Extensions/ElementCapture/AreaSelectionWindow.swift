//
//  AreaSelectionWindow.swift
//  Droppy
//
//  A fullscreen overlay for click-drag area selection (like Shottr)
//  Provides satisfying tactile feedback with snap animations
//

import SwiftUI
import AppKit

/// Fullscreen window for click-drag area selection
/// Captures a region when user clicks, drags, and releases
class AreaSelectionWindow: NSWindow {
    
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private var selectionView: AreaSelectionView?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown && event.keyCode == 53 {
            onCancel?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
    
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        
        // Configure window for fullscreen overlay
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .screenSaver
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
    
    func configure(onComplete: @escaping (CGRect) -> Void) {
        self.onSelectionComplete = onComplete
        
        // Create the selection view
        let view = AreaSelectionView(frame: NSRect(origin: .zero, size: contentRect(forFrameRect: frame).size))
        view.onSelectionComplete = { [weak self] rect in
            self?.onSelectionComplete?(rect)
        }
        view.onCancel = { [weak self] in
            self?.onCancel?()
        }
        
        self.contentView = view
        self.initialFirstResponder = view
        self.selectionView = view
    }

    func presentForCapture() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        if let selectionView {
            makeFirstResponder(selectionView)
            invalidateCursorRects(for: selectionView)
        }
        NSCursor.crosshair.set()

        // Re-apply focus/cursor on next runloop to avoid first-click activation behavior.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.makeKeyAndOrderFront(nil)
            if let selectionView = self.selectionView {
                self.makeFirstResponder(selectionView)
                self.invalidateCursorRects(for: selectionView)
            }
            NSCursor.crosshair.set()
        }
    }
}

/// The actual view that handles mouse interaction and draws the selection rectangle
class AreaSelectionView: NSView {
    
    var onSelectionComplete: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?
    
    private var isDragging = false
    private var startPoint: CGPoint = .zero
    private var currentPoint: CGPoint = .zero
    private var hasSnapped = false  // Track if we've crossed the minimum threshold
    
    private let selectionColor = NSColor.systemCyan.withAlphaComponent(0.3)
    private let borderColor = NSColor.systemCyan
    private let borderWidth: CGFloat = 2.0
    private let cornerRadius: CGFloat = 6.0
    private let minimumSize: CGFloat = 20.0  // Minimum size before "snap" feedback
    
    // Dimension label layer
    private var dimensionLabel: CATextLayer?
    private var cursorTrackingArea: NSTrackingArea?
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Subtle dark overlay so user knows capture mode is active
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.15).cgColor
        
        // Add dimension label
        setupDimensionLabel()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        window?.makeFirstResponder(self)
        window?.invalidateCursorRects(for: self)
        NSCursor.crosshair.set()
    }

    override func updateTrackingAreas() {
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }

        let options: NSTrackingArea.Options = [
            .activeAlways,
            .inVisibleRect,
            .mouseMoved,
            .cursorUpdate
        ]

        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        cursorTrackingArea = area

        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
    }
    
    private func setupDimensionLabel() {
        let label = CATextLayer()
        label.fontSize = 12
        label.foregroundColor = NSColor.white.cgColor
        label.backgroundColor = NSColor.black.withAlphaComponent(0.7).cgColor
        label.cornerRadius = 4
        label.alignmentMode = .center
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        label.isHidden = true
        layer?.addSublayer(label)
        dimensionLabel = label
    }
    
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    
    override func keyDown(with event: NSEvent) {
        // ESC to cancel
        if event.keyCode == 53 {
            onCancel?()
            return
        }
        super.keyDown(with: event)
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        startPoint = location
        currentPoint = location
        isDragging = true
        hasSnapped = false
        
        HapticFeedback.tap()
        setNeedsDisplay(bounds)
    }
    
    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        
        currentPoint = convert(event.locationInWindow, from: nil)
        
        // Check if we've crossed the minimum threshold for "snap" feedback
        let selectionRect = calculateSelectionRect()
        if !hasSnapped && selectionRect.width > minimumSize && selectionRect.height > minimumSize {
            hasSnapped = true
            HapticFeedback.select()  // Satisfying snap feedback
        }
        
        setNeedsDisplay(bounds)
        updateDimensionLabel()
    }
    
    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        
        isDragging = false
        currentPoint = convert(event.locationInWindow, from: nil)
        
        let selectionRect = calculateSelectionRect()
        
        // Only complete if the selection is large enough
        if selectionRect.width > 10 && selectionRect.height > 10 {
            HapticFeedback.drop()  // Strong "captured" feedback
            onSelectionComplete?(selectionRect)
        } else {
            // Too small, cancel
            onCancel?()
        }
    }
    
    private func calculateSelectionRect() -> CGRect {
        let minX = min(startPoint.x, currentPoint.x)
        let minY = min(startPoint.y, currentPoint.y)
        let width = abs(currentPoint.x - startPoint.x)
        let height = abs(currentPoint.y - startPoint.y)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }
    
    private func updateDimensionLabel() {
        guard let label = dimensionLabel else { return }
        
        let rect = calculateSelectionRect()
        guard rect.width > 30 && rect.height > 20 else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            label.isHidden = true
            CATransaction.commit()
            return
        }
        
        // Show dimensions
        let text = "\(Int(rect.width)) × \(Int(rect.height))"
        
        // Use CATransaction to disable implicit animations for snappy positioning
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        label.string = " \(text) "
        label.isHidden = false
        
        // Size to fit content
        let textWidth = max(70, min(100, CGFloat(text.count) * 8))
        let labelSize = CGSize(width: textWidth, height: 18)
        
        // Position at bottom center of selection (or top if near bottom of screen)
        var labelY = rect.minY - labelSize.height - 6
        if labelY < 20 {
            labelY = rect.maxY + 6
        }
        
        label.frame = CGRect(
            x: rect.midX - labelSize.width / 2,
            y: labelY,
            width: labelSize.width,
            height: labelSize.height
        )
        
        CATransaction.commit()
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        guard isDragging else { return }
        
        let selectionRect = calculateSelectionRect()
        guard selectionRect.width > 2 && selectionRect.height > 2 else { return }
        
        // Draw filled selection area
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: cornerRadius, yRadius: cornerRadius)
        selectionColor.setFill()
        path.fill()
        
        // Draw border
        borderColor.setStroke()
        path.lineWidth = borderWidth
        path.stroke()
        
        // Draw corner handles for visual polish
        drawCornerHandles(in: selectionRect)
    }
    
    private func drawCornerHandles(in rect: CGRect) {
        let handleSize: CGFloat = 8
        let handleColor = NSColor.white
        
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.minX, y: rect.maxY),
            CGPoint(x: rect.maxX, y: rect.maxY)
        ]
        
        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize / 2,
                y: corner.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            
            // White fill with cyan border
            let handlePath = NSBezierPath(ovalIn: handleRect)
            handleColor.setFill()
            handlePath.fill()
            borderColor.setStroke()
            handlePath.lineWidth = 1.5
            handlePath.stroke()
        }
    }
}
