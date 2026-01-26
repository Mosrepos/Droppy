//
//  DroppyBarConfigView.swift
//  Droppy
//
//  Configuration view for selecting which menu bar icons to show in Droppy Bar.
//  Selected icons will be hidden from the main menu bar and shown in Droppy Bar.
//

import SwiftUI
import AppKit

/// Configuration sheet for Droppy Bar
struct DroppyBarConfigView: View {
    let onDismiss: () -> Void
    
    @State private var menuBarItems: [MenuBarItem] = []
    @State private var selectedItemIds: Set<CGWindowID> = []
    @State private var isLoading = true
    
    private var itemStore: DroppyBarItemStore {
        MenuBarManager.shared.getDroppyBarItemStore()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Configure Droppy Bar")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    saveSelection()
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            
            Divider()
            
            // Instructions
            Text("Toggle items to move them to the Droppy Bar. They will be hidden from the main menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .padding(.top, 8)
            
            // Item list
            if isLoading {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Scanning menu bar...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if menuBarItems.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text("No menu bar items found")
                        .font(.callout)
                    Text("Make sure screen recording is enabled in System Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(menuBarItems) { item in
                        MenuBarItemRow(
                            item: item,
                            isSelected: selectedItemIds.contains(item.windowID),
                            onToggle: { isSelected in
                                if isSelected {
                                    selectedItemIds.insert(item.windowID)
                                } else {
                                    selectedItemIds.remove(item.windowID)
                                }
                            }
                        )
                    }
                }
            }
        }
        .frame(width: 450, height: 500)
        .onAppear {
            loadMenuBarItems()
        }
    }
    
    private func loadMenuBarItems() {
        isLoading = true
        
        Task { @MainActor in
            // Get all menu bar items - be inclusive!
            let allItems = MenuBarItem.getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)
            
            // Filter out our own toggle and system items that shouldn't be moved
            menuBarItems = allItems.filter { item in
                // Keep most items, only filter our own controls
                !item.ownerName.contains("Droppy") &&
                item.ownerName != "SystemUIServer" // Keep Control Center items by owner name
            }
            
            // Load current selection from store
            let storedBundleIds = itemStore.enabledBundleIds
            for item in menuBarItems {
                if let bundleId = item.owningApplication?.bundleIdentifier,
                   storedBundleIds.contains(bundleId) {
                    selectedItemIds.insert(item.windowID)
                }
            }
            
            isLoading = false
            print("[DroppyBarConfig] Found \(menuBarItems.count) menu bar items")
        }
    }
    
    private func saveSelection() {
        // Clear existing items
        itemStore.clearAll()
        
        // Add selected items
        var position = 0
        for windowId in selectedItemIds {
            guard let item = menuBarItems.first(where: { $0.windowID == windowId }) else { continue }
            
            let bundleId = item.owningApplication?.bundleIdentifier ?? "unknown.\(item.ownerName)"
            let droppyItem = DroppyBarItem(
                bundleIdentifier: bundleId,
                displayName: item.displayName,
                position: position
            )
            itemStore.addItem(droppyItem)
            position += 1
        }
        
        print("[DroppyBarConfig] Saved \(position) items")
    }
}

/// Row view for a menu bar item
struct MenuBarItemRow: View {
    let item: MenuBarItem
    let isSelected: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon (from app or captured image)
            Group {
                if let app = item.owningApplication, let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "menubar.rectangle")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            
            // Name and bundle ID
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)
                    .lineLimit(1)
                
                if let bundleId = item.owningApplication?.bundleIdentifier {
                    Text(bundleId)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Toggle
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { onToggle($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DroppyBarConfigView(onDismiss: {})
}
