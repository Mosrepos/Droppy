//
//  TerminalNotchManager.swift
//  Droppy
//
//  Manages terminal state, process, and keyboard shortcuts
//

import SwiftUI
import AppKit
import Combine

/// Manages the Terminal-Notch extension state and terminal process
@MainActor
class TerminalNotchManager: ObservableObject {
    static let shared = TerminalNotchManager()
    
    // MARK: - Published State
    
    /// Whether the terminal overlay is visible
    @Published var isVisible: Bool = false
    
    /// Whether we're in expanded mode (full terminal) vs quick command mode
    @Published var isExpanded: Bool = false
    
    /// Current command input text (for quick mode)
    @Published var commandText: String = ""
    
    /// Command history
    @Published var commandHistory: [String] = []
    
    /// Current history index for navigation
    @Published var historyIndex: Int = -1
    
    /// Last command output (for quick mode feedback)
    @Published var lastOutput: String = ""
    
    /// Is command currently running
    @Published var isRunning: Bool = false
    
    /// Pulse animation trigger (set briefly on command execution)
    @Published var showPulse: Bool = false
    
    /// Pulse position for sweeping animation (0 to 1)
    @Published var pulsePosition: CGFloat = 0
    
    /// Whether any command has been executed in this terminal session
    @Published var hasExecutedCommand: Bool = false
    
    // MARK: - Settings
    
    /// Whether extension is installed
    @AppStorage(AppPreferenceKey.terminalNotchInstalled) var isInstalled: Bool = PreferenceDefault.terminalNotchInstalled
    
    /// Saved keyboard shortcut
    @Published var shortcut: SavedShortcut? = nil
    
    // MARK: - Private
    
    private var cancellables = Set<AnyCancellable>()
    private var process: Process?
    private var outputPipe: Pipe?
    private var inputPipe: Pipe?
    private var globalMonitor: Any?
    
    private init() {
        loadHistory()
        loadShortcut()
        registerShortcut()
    }
    
    // MARK: - Public Methods
    
    /// Toggle terminal visibility
    func toggle() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isVisible.toggle()
            if isVisible {
                // CRITICAL: Also expand the shelf - terminal renders inside expanded shelf
                // Open on the screen where cursor is (consistent with all shelf/island behavior)
                let mouseLocation = NSEvent.mouseLocation
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
                    DroppyState.shared.expandShelf(for: screen.displayID)
                } else if let mainScreen = NSScreen.main {
                    DroppyState.shared.expandShelf(for: mainScreen.displayID)
                }
                // Focus the terminal when shown
                focusTerminal()
            } else {
                // Collapse shelf when hiding terminal
                DroppyState.shared.expandedDisplayID = nil
            }
        }
    }
    
    /// Show terminal
    func show() {
        guard !isVisible else { return }
        toggle()
    }
    
    /// Hide terminal
    func hide() {
        guard isVisible else { return }
        toggle()
    }
    
    /// Toggle between quick and expanded mode
    func toggleExpanded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }
    }
    
    /// Clear terminal output (start fresh)
    func clearOutput() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            lastOutput = ""
            commandText = ""
            hasExecutedCommand = false
        }
    }
    
    /// Execute a quick command (non-interactive)
    func executeQuickCommand(_ command: String) {
        guard !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Add to history
        addToHistory(command)
        
        isRunning = true
        hasExecutedCommand = true
        lastOutput = ""
        
        // Trigger sweeping pulse animation
        showPulse = true
        pulsePosition = 0
        
        // Animate position from 0 to past 1 (so the pulse sweeps completely across)
        withAnimation(.easeInOut(duration: 0.6)) {
            pulsePosition = 1.15
        }
        
        // Hide pulse after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            self.showPulse = false
            self.pulsePosition = 0
        }
        
        Task {
            do {
                let output = try await runCommand(command)
                await MainActor.run {
                    self.lastOutput = output
                    self.isRunning = false
                    self.commandText = ""
                }
            } catch {
                await MainActor.run {
                    self.lastOutput = "Error: \(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        }
    }
    
    /// Open Terminal.app (no automation - just launches the app)
    func openInTerminalApp() {
        // Use NSWorkspace to simply open Terminal.app
        // This doesn't require any special permissions
        if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
            NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
    
    /// Navigate command history up
    func historyUp() {
        guard !commandHistory.isEmpty else { return }
        if historyIndex < commandHistory.count - 1 {
            historyIndex += 1
            commandText = commandHistory[commandHistory.count - 1 - historyIndex]
        }
    }
    
    /// Navigate command history down
    func historyDown() {
        if historyIndex > 0 {
            historyIndex -= 1
            commandText = commandHistory[commandHistory.count - 1 - historyIndex]
        } else if historyIndex == 0 {
            historyIndex = -1
            commandText = ""
        }
    }
    
    /// Cleanup when extension is removed
    func cleanup() {
        isVisible = false
        isExpanded = false
        commandHistory = []
        isInstalled = false
        
        // Remove keyboard shortcut
        removeShortcut()
        
        // Clear history from disk
        UserDefaults.standard.removeObject(forKey: "terminalNotch_history")
    }
    
    // MARK: - Private Methods
    
    private func focusTerminal() {
        // Will be handled by the view
        historyIndex = -1
    }
    
    private func addToHistory(_ command: String) {
        // Don't add duplicates of the last command
        if commandHistory.last != command {
            commandHistory.append(command)
            // Keep last 100 commands
            if commandHistory.count > 100 {
                commandHistory.removeFirst()
            }
            saveHistory()
        }
        historyIndex = -1
    }
    
    private func loadHistory() {
        if let history = UserDefaults.standard.stringArray(forKey: "terminalNotch_history") {
            commandHistory = history
        }
    }
    
    private func saveHistory() {
        UserDefaults.standard.set(commandHistory, forKey: "terminalNotch_history")
    }
    
    /// Run a shell command and return output (with timeout and output limit)
    private func runCommand(_ command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // Use -l for login shell (sources profile with PATH including brew)
            // and -c to run the command
            process.arguments = ["-l", "-c", command]
            process.standardOutput = pipe
            process.standardError = pipe
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            
            // SAFETY: Timeout to prevent freeze with continuous commands (ping, tail -f, etc.)
            let timeout: TimeInterval = 10.0  // 10 second timeout
            let maxOutputBytes = 50_000  // Limit output to ~50KB to prevent memory issues
            
            var outputData = Data()
            var hasResumed = false
            let resumeLock = NSLock()
            
            // Helper to safely resume continuation only once
            func safeResume(with result: Result<String, Error>) {
                resumeLock.lock()
                defer { resumeLock.unlock() }
                guard !hasResumed else { return }
                hasResumed = true
                switch result {
                case .success(let output):
                    continuation.resume(returning: output)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            
            do {
                try process.run()
                
                // Set up timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                    if process.isRunning {
                        process.terminate()
                        // Read whatever output we have
                        let data = pipe.fileHandleForReading.availableData
                        let output = String(data: data, encoding: .utf8) ?? ""
                        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                        let message = trimmed.isEmpty 
                            ? "⏱️ Command timed out after \(Int(timeout))s (continuous output commands like 'ping' are not supported)"
                            : trimmed + "\n\n⏱️ Command timed out after \(Int(timeout))s"
                        safeResume(with: .success(message))
                    }
                }
                
                // Read output in background with size limit
                DispatchQueue.global().async {
                    let fileHandle = pipe.fileHandleForReading
                    while process.isRunning {
                        let chunk = fileHandle.availableData
                        if chunk.isEmpty { break }
                        outputData.append(chunk)
                        
                        // Safety: terminate if output is too large
                        if outputData.count > maxOutputBytes {
                            process.terminate()
                            break
                        }
                    }
                    
                    // Process finished normally - read any remaining data
                    if !process.isRunning {
                        let remaining = fileHandle.readDataToEndOfFile()
                        if outputData.count + remaining.count <= maxOutputBytes {
                            outputData.append(remaining)
                        }
                    }
                    
                    let output = String(data: outputData, encoding: .utf8) ?? ""
                    var trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Add warning if output was truncated
                    if outputData.count > maxOutputBytes {
                        trimmed += "\n\n⚠️ Output truncated (exceeded \(maxOutputBytes / 1000)KB limit)"
                    }
                    
                    safeResume(with: .success(trimmed))
                }
            } catch {
                safeResume(with: .failure(error))
            }
        }
    }
    
    // MARK: - Shortcut Management
    
    private func loadShortcut() {
        if let data = UserDefaults.standard.data(forKey: "terminalNotch_shortcut"),
           let saved = try? JSONDecoder().decode(SavedShortcut.self, from: data) {
            shortcut = saved
        }
    }
    
    private func saveShortcut() {
        if let shortcut = shortcut,
           let data = try? JSONEncoder().encode(shortcut) {
            UserDefaults.standard.set(data, forKey: "terminalNotch_shortcut")
        } else {
            UserDefaults.standard.removeObject(forKey: "terminalNotch_shortcut")
        }
    }
    
    /// Register global keyboard shortcut for terminal toggle
    func registerShortcut() {
        // Remove existing monitor
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        
        guard let shortcut = shortcut, isInstalled else { return }
        
        // Create new global monitor
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return }
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if Int(event.keyCode) == shortcut.keyCode && flags.rawValue == shortcut.modifiers {
                Task { @MainActor in
                    self.toggle()
                }
            }
        }
        
        // Also monitor local events (when app is focused)
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, let shortcut = self.shortcut, self.isInstalled else { return event }
            
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if Int(event.keyCode) == shortcut.keyCode && flags.rawValue == shortcut.modifiers {
                Task { @MainActor in
                    self.toggle()
                }
                return nil // Consume the event
            }
            return event
        }
        
        saveShortcut()
    }
    
    /// Remove shortcut
    func removeShortcut() {
        shortcut = nil
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        UserDefaults.standard.removeObject(forKey: "terminalNotch_shortcut")
    }
}
