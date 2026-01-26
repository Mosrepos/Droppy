//
//  MenuBarItem.swift
//  Droppy
//
//  Model for menu bar items, modeled after Ice's implementation.
//  Provides access to window info, frame, and owner details.
//

import Cocoa

/// Represents a menu bar status item window
struct MenuBarItem: Identifiable, Equatable, Hashable {
    /// The window identifier for this item
    let windowID: CGWindowID
    
    /// The title of the window (if any)
    let title: String?
    
    /// The owning application's name
    let ownerName: String
    
    /// The owning application's PID
    let ownerPID: pid_t
    
    /// The frame of the item in screen coordinates
    let frame: CGRect
    
    /// Whether the item is currently on screen
    let isOnScreen: Bool
    
    // MARK: - Identifiable
    
    var id: CGWindowID { windowID }
    
    // MARK: - Computed Properties
    
    /// Display name for the item (owner name or title)
    var displayName: String {
        title ?? ownerName
    }
    
    /// The owning application
    var owningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: ownerPID)
    }
    
    // MARK: - Initialization
    
    /// Creates a MenuBarItem from a window info dictionary
    init?(windowInfo: [String: Any]) {
        guard
            let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
            let ownerName = windowInfo[kCGWindowOwnerName as String] as? String,
            let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
            let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
            let x = boundsDict["X"],
            let y = boundsDict["Y"],
            let width = boundsDict["Width"],
            let height = boundsDict["Height"]
        else {
            return nil
        }
        
        self.windowID = windowID
        self.title = windowInfo[kCGWindowName as String] as? String
        self.ownerName = ownerName
        self.ownerPID = ownerPID
        self.frame = CGRect(x: x, y: y, width: width, height: height)
        self.isOnScreen = (windowInfo[kCGWindowIsOnscreen as String] as? Bool) ?? false
    }
    
    /// Creates a MenuBarItem by looking up a window ID
    init?(windowID: CGWindowID) {
        guard let windowInfoList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let windowInfo = windowInfoList.first else {
            return nil
        }
        self.init(windowInfo: windowInfo)
    }
    
    // MARK: - Static Methods
    
    /// Gets all menu bar items
    /// - Parameters:
    ///   - onScreenOnly: If true, only returns items currently visible
    ///   - activeSpaceOnly: If true, only returns items in the active space
    /// - Returns: Array of MenuBarItem sorted by X position (right to left)
    static func getMenuBarItems(onScreenOnly: Bool = true, activeSpaceOnly: Bool = true) -> [MenuBarItem] {
        var options: CGWindowListOption = []
        if onScreenOnly {
            options.insert(.optionOnScreenOnly)
        }
        
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            print("[MenuBarItem] CGWindowListCopyWindowInfo returned nil")
            return []
        }
        
        // Get the menu bar height to filter by Y position
        guard let screen = NSScreen.main else {
            print("[MenuBarItem] No main screen")
            return []
        }
        let menuBarMaxY: CGFloat = 30 // Menu bar items are in top ~30 pixels
        
        // Multiple window levels that menu bar items can be at
        let statusWindowLevel = Int(CGWindowLevelForKey(.statusWindow))
        let mainMenuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))
        let popUpMenuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        
        print("[MenuBarItem] Scanning \(windowInfoList.count) windows for menu bar items")
        print("[MenuBarItem] Status level: \(statusWindowLevel), MainMenu level: \(mainMenuLevel)")
        
        var items: [MenuBarItem] = []
        var debugItems: [(String, Int, CGRect)] = []
        
        for windowInfo in windowInfoList {
            guard let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
                  let y = boundsDict["Y"],
                  let height = boundsDict["Height"],
                  let width = boundsDict["Width"] else {
                continue
            }
            
            let ownerName = windowInfo[kCGWindowOwnerName as String] as? String ?? "Unknown"
            
            // Track windows near the menu bar for debugging
            if y < 50 && height < 50 && height > 0 && width > 0 {
                debugItems.append((ownerName, layer, CGRect(
                    x: boundsDict["X"] ?? 0,
                    y: y,
                    width: width,
                    height: height
                )))
            }
            
            // Menu bar items should be:
            // 1. Near the top of the screen (Y < menuBarMaxY)
            // 2. At status window level OR main menu level
            // 3. Have a reasonable size (height < 30, width > 0)
            let isMenuBarHeight = y < menuBarMaxY && height > 0 && height < 40
            let isMenuBarLevel = layer == statusWindowLevel || layer == mainMenuLevel || layer == 25 // 25 is common menu bar layer
            
            guard isMenuBarHeight && isMenuBarLevel else {
                continue
            }
            
            guard let item = MenuBarItem(windowInfo: windowInfo) else {
                continue
            }
            
            // Skip Window Server
            if item.ownerName == "Window Server" {
                continue
            }
            
            // Skip Droppy's own items
            if item.ownerName == "Droppy" {
                continue
            }
            
            items.append(item)
        }
        
        // Debug output
        print("[MenuBarItem] Found windows near menu bar:")
        for (name, layer, frame) in debugItems {
            print("  - \(name) (layer: \(layer)) frame: \(frame)")
        }
        print("[MenuBarItem] Returning \(items.count) menu bar items")
        
        // Sort by X position (right to left in menu bar)
        return items.sorted { $0.frame.minX > $1.frame.minX }
    }
    
    /// Gets menu bar items for a specific section (hidden vs visible)
    /// - Parameter hidden: If true, returns hidden items; if false, returns visible items
    /// - Returns: Array of MenuBarItem
    static func getHiddenMenuBarItems() -> [MenuBarItem] {
        // Get all items including offscreen
        return getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)
            .filter { !$0.isOnScreen }
    }
    
    /// Gets the current frame of a menu bar item by window ID
    static func getCurrentFrame(for windowID: CGWindowID) -> CGRect? {
        guard let item = MenuBarItem(windowID: windowID) else {
            return nil
        }
        return item.frame
    }
}

// MARK: - MenuBarItemInfo

/// Lightweight identifier for a menu bar item (used as dictionary key)
struct MenuBarItemInfo: Hashable, Codable {
    let windowID: CGWindowID
    let ownerName: String
    let ownerPID: pid_t
    
    init(item: MenuBarItem) {
        self.windowID = item.windowID
        self.ownerName = item.ownerName
        self.ownerPID = item.ownerPID
    }
    
    init(windowID: CGWindowID, ownerName: String, ownerPID: pid_t) {
        self.windowID = windowID
        self.ownerName = ownerName
        self.ownerPID = ownerPID
    }
}

extension MenuBarItem {
    /// Creates an info struct for this item
    var info: MenuBarItemInfo {
        MenuBarItemInfo(item: self)
    }
}
