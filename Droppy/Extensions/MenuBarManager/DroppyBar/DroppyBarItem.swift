//
//  DroppyBarItem.swift
//  Droppy
//
//  Model for an item displayed in the Droppy Bar.
//

import Cocoa
import Combine

/// Represents a menu bar item that can be displayed in the Droppy Bar
struct DroppyBarItem: Identifiable, Codable, Equatable {
    
    /// Unique identifier
    var id: String { bundleIdentifier }
    
    /// The bundle identifier of the app that owns this menu bar item
    let bundleIdentifier: String
    
    /// Display name for tooltips and accessibility
    var displayName: String
    
    /// Position in the Droppy Bar (lower = more left)
    var position: Int
    
    /// Whether this item is currently visible in the Droppy Bar
    var isVisible: Bool = true
    
    // MARK: - Initialization
    
    init(bundleIdentifier: String, displayName: String, position: Int = 0) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.position = position
    }
    
    // MARK: - Icon
    
    /// Get the icon for this item from the app bundle
    var icon: NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

// MARK: - DroppyBarItemStore

/// Manages persistence of Droppy Bar items
@MainActor
final class DroppyBarItemStore: ObservableObject {
    
    /// Published list of items in the Droppy Bar
    @Published var items: [DroppyBarItem] = []
    
    /// UserDefaults key for storing items
    private let storageKey = "DroppyBarItems"
    
    // MARK: - Initialization
    
    init() {
        loadItems()
    }
    
    // MARK: - Persistence
    
    /// Load items from UserDefaults
    func loadItems() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([DroppyBarItem].self, from: data) else {
            // Default items (empty for now)
            items = []
            return
        }
        items = decoded.sorted { $0.position < $1.position }
    }
    
    /// Save items to UserDefaults
    func saveItems() {
        guard let encoded = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(encoded, forKey: storageKey)
    }
    
    // MARK: - Item Management
    
    /// Add an item to the Droppy Bar
    func addItem(_ item: DroppyBarItem) {
        var newItem = item
        newItem.position = items.count
        items.append(newItem)
        saveItems()
    }
    
    /// Remove an item from the Droppy Bar
    func removeItem(bundleIdentifier: String) {
        items.removeAll { $0.bundleIdentifier == bundleIdentifier }
        reorderPositions()
        saveItems()
    }
    
    /// Move an item to a new position
    func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              sourceIndex >= 0, sourceIndex < items.count,
              destinationIndex >= 0, destinationIndex < items.count else { return }
        
        let item = items.remove(at: sourceIndex)
        items.insert(item, at: destinationIndex)
        reorderPositions()
        saveItems()
    }
    
    /// Reorder positions after changes
    private func reorderPositions() {
        for (index, _) in items.enumerated() {
            items[index].position = index
        }
    }
    
    /// Get bundle IDs of visible items
    var enabledBundleIds: Set<String> {
        Set(items.filter { $0.isVisible }.map { $0.bundleIdentifier })
    }
    
    /// Check if an item exists
    func hasItem(bundleIdentifier: String) -> Bool {
        items.contains { $0.bundleIdentifier == bundleIdentifier }
    }
    
    /// Clear all items
    func clearAll() {
        items.removeAll()
        saveItems()
    }
}
