//
//  MenuBarItemImageCache.swift
//  Droppy
//
//  Caches menu bar item images using CGWindowListCreateImage.
//  Based on Ice's MenuBarItemImageCache implementation.
//

import Cocoa
import Combine

/// Cache for menu bar item images captured via screen capture
@MainActor
final class MenuBarItemImageCache: ObservableObject {
    
    /// The cached item images, keyed by item info
    @Published private(set) var images = [MenuBarItemInfo: CGImage]()
    
    /// The screen the images were captured from
    private(set) var screen: NSScreen?
    
    /// The menu bar height when images were captured
    private(set) var menuBarHeight: CGFloat?
    
    /// Storage for observers
    private var cancellables = Set<AnyCancellable>()
    
    /// Timer for periodic updates
    private var updateTimer: Timer?
    
    // MARK: - Initialization
    
    init() {
        startPeriodicUpdates()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Periodic Updates
    
    private func startPeriodicUpdates() {
        // Update every 3 seconds like Ice does
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateCache()
            }
        }
    }
    
    // MARK: - Cache Management
    
    /// Update the image cache for all menu bar items
    func updateCache() async {
        guard let screen = NSScreen.main else { return }
        
        // Check screen capture permission
        guard CGPreflightScreenCaptureAccess() else {
            print("[ImageCache] No screen capture permission")
            return
        }
        
        // Get all menu bar items (including hidden ones)
        let items = MenuBarItem.getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)
        
        guard !items.isEmpty else {
            print("[ImageCache] No items found")
            return
        }
        
        let backingScaleFactor = screen.backingScaleFactor
        var newImages = [MenuBarItemInfo: CGImage]()
        
        // Capture each item individually
        for item in items {
            guard item.frame.width > 0 && item.frame.height > 0 else { continue }
            
            if let image = captureItemImage(item: item, backingScaleFactor: backingScaleFactor) {
                newImages[item.info] = image
            }
        }
        
        self.images = newImages
        self.screen = screen
        self.menuBarHeight = 24 // Standard menu bar height
        
        print("[ImageCache] Updated cache with \(newImages.count) images")
    }
    
    /// Capture a single menu bar item's image
    private func captureItemImage(item: MenuBarItem, backingScaleFactor: CGFloat) -> CGImage? {
        // Use CGWindowListCreateImage with the specific window ID
        let windowID = item.windowID
        
        // Capture just this window
        guard let image = CGWindowListCreateImage(
            .null,  // Null rect = capture full window
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }
        
        return image
    }
    
    /// Get an NSImage for a menu bar item (convenience method)
    func getImage(for item: MenuBarItem) -> NSImage? {
        guard let cgImage = images[item.info],
              let screen = screen else {
            return nil
        }
        
        let size = CGSize(
            width: CGFloat(cgImage.width) / screen.backingScaleFactor,
            height: CGFloat(cgImage.height) / screen.backingScaleFactor
        )
        
        return NSImage(cgImage: cgImage, size: size)
    }
    
    /// Force an immediate refresh of the cache
    func refreshNow() async {
        await updateCache()
    }
}
