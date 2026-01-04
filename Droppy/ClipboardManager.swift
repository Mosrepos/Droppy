import SwiftUI
import AppKit
import Combine

enum ClipboardType: String, Codable {
    case text
    case image
    case file
    case url
    case color
}

struct ClipboardItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var type: ClipboardType
    var content: String? // Text, URL string, or File path
    var imageData: Data? // For images
    var date: Date = Date()
    var sourceApp: String?
    var isFavorite: Bool = false
    var customTitle: String? // User-defined title for easy finding
    
    var title: String {
        // Use custom title if set
        if let custom = customTitle, !custom.isEmpty {
            return custom
        }
        // Otherwise generate from content
        switch type {
        case .text:
            return content?.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50).description ?? "Text"
        case .image:
            return "Image"
        case .file:
            return URL(fileURLWithPath: content ?? "").lastPathComponent
        case .url:
            return content ?? "Link"
        case .color:
            return "Color"
        }
    }
}

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var history: [ClipboardItem] = [] {
        didSet {
            saveToDisk()
        }
    }
    @Published var hasAccessibilityPermission: Bool = false
    @Published var showPasteFeedback: Bool = false
    @AppStorage("enableClipboardBeta") var isEnabled: Bool = false
    @AppStorage("clipboardHistoryLimit") var historyLimit: Int = 50
    
    private var lastChangeCount: Int
    private var timer: Timer?
    
    private var persistenceURL: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("Droppy", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("clipboard_history.json")
    }
    
    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
        self.hasAccessibilityPermission = AXIsProcessTrusted()
        loadFromDisk()
        if isEnabled {
            startMonitoring()
        }
    }
    
    func checkPermission() {
        let trusted = AXIsProcessTrusted()
        if hasAccessibilityPermission != trusted {
            DispatchQueue.main.async {
                self.hasAccessibilityPermission = trusted
            }
        }
    }
    
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(history)
            try data.write(to: persistenceURL)
        } catch {
            print("Failed to save clipboard history: \(error)")
        }
    }
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let decoded = try JSONDecoder().decode([ClipboardItem].self, from: data)
            DispatchQueue.main.async {
                self.history = decoded
            }
        } catch {
            print("Failed to load clipboard history: \(error)")
        }
    }
    
    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            autoreleasepool {
                self?.checkForChanges()
                self?.checkPermission()
            }
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func enforceHistoryLimit() {
        if history.count > historyLimit {
            history = Array(history.prefix(historyLimit))
        }
    }

    private func checkForChanges() {
        guard isEnabled else { return }
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        
        lastChangeCount = currentCount
        
        // Extract content
        let pasteboard = NSPasteboard.general
        let bestItem = extractItem(from: pasteboard)
        
        if var item = bestItem {
            DispatchQueue.main.async {
                // Check if this item already exists in history
                if let index = self.history.firstIndex(where: { $0.content == item.content && $0.type == item.type }) {
                    // It exists!
                    // 1. Preserve user customizations (Favorite status, Custom Title)
                    let existing = self.history[index]
                    item.isFavorite = existing.isFavorite
                    item.customTitle = existing.customTitle
                    
                    // 2. Remove the old one so we don't have duplicates
                    self.history.remove(at: index)
                }
                
                // 3. Insert the new (or refreshed) item at the top
                self.history.insert(item, at: 0)
                
                // Limit history based on user setting
                self.enforceHistoryLimit()
            }
        }
    }
    
    private func extractItem(from pasteboard: NSPasteboard) -> ClipboardItem? {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        
        // 1. Check for URL
        if let urlStr = pasteboard.string(forType: .URL) {
            return ClipboardItem(type: .url, content: urlStr, sourceApp: app)
        }
        
        // 2. Check for File URL
        if let fileURLVal = pasteboard.propertyList(forType: .fileURL) as? String,
           let url = URL(string: fileURLVal) {
             return ClipboardItem(type: .file, content: url.path, sourceApp: app)
        }
        
        // 3. Check for Text
        if let str = pasteboard.string(forType: .string) {
            return ClipboardItem(type: .text, content: str, sourceApp: app)
        }
        
        // 4. Check for Image
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation {
             // Compress/Resize for storage? For now, raw.
             // Warning: This can be memory heavy.
             // Let's store a small thumbnail or just the full data if small?
             // For beta, let's keep it simple but be careful.
             return ClipboardItem(type: .image, imageData: tiff, sourceApp: app)
        }
        
        return nil
    }
    
    func paste(item: ClipboardItem, targetPID: pid_t? = nil) {
        // Re-check permission right before simulation
        checkPermission()
        
        // Show feedback toast in UI
        DispatchQueue.main.async {
            self.showPasteFeedback = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.showPasteFeedback = false
            }
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        switch item.type {
        case .text:
            if let str = item.content {
                pasteboard.setString(str, forType: .string)
            }
        case .url:
            if let str = item.content {
                pasteboard.setString(str, forType: .URL)
                pasteboard.setString(str, forType: .string)
            }
        case .file:
            if let path = item.content {
                pasteboard.writeObjects([URL(fileURLWithPath: path) as NSURL])
            }
        case .image:
            if let data = item.imageData, let img = NSImage(data: data) {
                pasteboard.writeObjects([img])
            }
        default: break
        }
        
        // Precisely mirroring ClipBook: The simulation happens immediately here;
        // the caller (WindowController) handles the 150ms "focus settling" delay.
        self.simulatePasteCommand(targetPID: targetPID)
    }
    
    private func simulatePasteCommand(targetPID: pid_t?) {
        // EXACT Mirror of ClipBook Method (V12):
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // 'v'
        
        // Create Down event with Command flag
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true) else { return }
        keyDown.flags = .maskCommand
        
        // Create Up event WITHOUT Command flag
        guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        
        // Post events with a tiny micro-delay to help complex editors (V12)
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        usleep(10000) // 10ms gap
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        
        print("🪞 Droppy: Paste mirrored from ClipBook V12 (PID: \(targetPID ?? 0))")
    }
    
    func toggleFavorite(_ item: ClipboardItem) {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history[index].isFavorite.toggle()
            // Move favorites to top? Or just mark them. 
            // User requirement: "stick to the top". 
            // Let's re-sort.
            sortHistory()
        }
    }
    
    private func sortHistory() {
        history.sort { (a, b) -> Bool in
            if a.isFavorite && !b.isFavorite { return true }
            if !a.isFavorite && b.isFavorite { return false }
            return a.date > b.date
        }
    }
    
    func delete(item: ClipboardItem) {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            history.remove(at: index)
        }
    }
    
    func rename(item: ClipboardItem, to newTitle: String) {
        if let index = history.firstIndex(where: { $0.id == item.id }) {
            let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            history[index].customTitle = trimmed.isEmpty ? nil : trimmed
        }
    }
}
