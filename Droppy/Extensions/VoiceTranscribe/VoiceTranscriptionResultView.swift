//
//  VoiceTranscriptionResultView.swift
//  Droppy
//
//  Result window showing transcribed text with copy option
//  Styled to match OCRResultView
//

import SwiftUI
import AppKit

// MARK: - Result Window Controller

@MainActor
final class VoiceTranscriptionResultController: NSObject, NSWindowDelegate {
    static let shared = VoiceTranscriptionResultController()
    
    private(set) var window: NSWindow?
    private var hostingView: NSHostingView<VoiceTranscriptionResultView>?
    private var isClosing = false
    private var deferredTeardownWorkItem: DispatchWorkItem?
    private let deferredTeardownDelay: TimeInterval = 8
    
    private override init() {
        super.init()
    }
    
    func showResult() {
        let result = VoiceTranscribeManager.shared.transcriptionResult
        guard !result.isEmpty else {
            print("VoiceTranscribe: No transcription result to show")
            return
        }
        
        show(with: result)
    }
    
    func show(with text: String) {
        let contentView = VoiceTranscriptionResultView(text: text) { [weak self] in
            self?.hideWindow()
        }
        cancelDeferredTeardown()

        if let hostingView {
            hostingView.rootView = contentView
        } else {
            hostingView = NSHostingView(rootView: contentView)
        }

        let panel: NSWindow
        if let existing = window {
            panel = existing
        } else {
            let newWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 400),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )

            newWindow.title = "Transcription"
            newWindow.titlebarAppearsTransparent = true
            newWindow.titleVisibility = .hidden
            newWindow.standardWindowButton(.closeButton)?.isHidden = true
            newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
            newWindow.standardWindowButton(.zoomButton)?.isHidden = true

            newWindow.isMovableByWindowBackground = true
            newWindow.backgroundColor = .clear
            newWindow.isOpaque = false
            newWindow.hasShadow = true
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            self.window = newWindow
            panel = newWindow
        }

        if let hostingView {
            panel.contentView = hostingView
        }

        if panel.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            AppKitMotion.prepareForPresent(panel, initialScale: 0.9)
            panel.orderFront(nil)
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                panel.makeKeyAndOrderFront(nil)
            }
            AppKitMotion.animateIn(panel, initialScale: 0.9, duration: 0.2)
        }

        print("VoiceTranscribe: Result window shown at center")
    }
    
    func hideWindow() {
        guard let panel = window, !isClosing else { return }
        cancelDeferredTeardown()
        isClosing = true

        AppKitMotion.animateOut(panel, targetScale: 0.96, duration: 0.15) { [weak self] in
            panel.orderOut(nil)
            AppKitMotion.resetPresentationState(panel)
            self?.isClosing = false
            self?.scheduleDeferredTeardown()
        }
    }

    private func scheduleDeferredTeardown() {
        deferredTeardownWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.window, !panel.isVisible else { return }
            panel.contentView = nil
            panel.delegate = nil
            self.window = nil
            self.hostingView = nil
            self.deferredTeardownWorkItem = nil
        }
        deferredTeardownWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + deferredTeardownDelay, execute: workItem)
    }

    private func cancelDeferredTeardown() {
        deferredTeardownWorkItem?.cancel()
        deferredTeardownWorkItem = nil
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        isClosing = false
        cancelDeferredTeardown()
        window = nil
        hostingView = nil
    }
}

// MARK: - Result View (matches OCRResultView style exactly)

struct VoiceTranscriptionResultView: View {
    let text: String
    let onClose: () -> Void
    
    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground
    @State private var showCopiedFeedback = false
    
    private var hasRecording: Bool {
        VoiceTranscribeManager.shared.lastRecordingURL != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Transcription")
                        .font(.headline)
                    Text("Speech recognized from audio")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(DroppySpacing.xl)
            
            Divider()
                .padding(.horizontal, 20)
            
            // Content
            ScrollView {
                Text(text)
                    .font(.body)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(DroppySpacing.xl)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 300)
            
            Divider()
                .padding(.horizontal, 20)
            
            // Action buttons
            HStack(spacing: 10) {
                Button {
                    // Discard recording on close
                    VoiceTranscribeManager.shared.discardRecording()
                    onClose()
                } label: {
                    Text("Close")
                }
                .buttonStyle(DroppyPillButtonStyle(size: .small))
                
                // Save Audio button
                if hasRecording {
                    Button {
                        VoiceTranscribeManager.shared.saveRecording()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Save Audio")
                        }
                    }
                    .buttonStyle(DroppyPillButtonStyle(size: .small))
                }
                
                Spacer()
                
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                    
                    withAnimation(DroppyAnimation.hover) {
                        showCopiedFeedback = true
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        onClose()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCopiedFeedback ? "checkmark" : "doc.on.doc")
                        Text(showCopiedFeedback ? "Copied!" : "Copy to Clipboard")
                    }
                }
                .buttonStyle(DroppyAccentButtonStyle(color: showCopiedFeedback ? .green : AdaptiveColors.selectionBlueAuto, size: .small))
            }
            .padding(DroppySpacing.lg)
        }
        .frame(width: 420)
        .fixedSize(horizontal: true, vertical: true)
        .droppyTransparentBackground(useTransparentBackground)
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.xl, style: .continuous))
    }
}

#Preview {
    VoiceTranscriptionResultView(text: "This is a sample transcription of some spoken audio.") {}
}
