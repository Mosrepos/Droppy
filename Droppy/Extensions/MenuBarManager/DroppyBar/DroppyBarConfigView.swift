//
//  DroppyBarConfigView.swift
//  Droppy
//
//  Configuration view for selecting which menu bar icons to show in Droppy Bar.
//

import SwiftUI
import AppKit

/// Configuration sheet for Droppy Bar
struct DroppyBarConfigView: View {
    let onDismiss: () -> Void
    
    @State private var menuBarItems: [MenuBarItem] = []
    @State private var selectedDisplayNames: Set<String> = []  // Use displayName as unique key
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
            Text("Toggle items to show them in the Droppy Bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
            
            // Debug info
            Text("Selected: \(selectedDisplayNames.count) items")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
            
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
                    Text("Screen recording: \(CGPreflightScreenCaptureAccess() ? "Authorized" : "Denied")")
                        .font(.caption)
                    Text("Check Console.app for [MenuBarItem] logs")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(menuBarItems) { item in
                        HStack(spacing: 12) {
                            // Icon
                            if let app = item.owningApplication, let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "menubar.rectangle")
                                    .frame(width: 24, height: 24)
                                    .foregroundStyle(.secondary)
                            }
                            
                            // Name - show displayName which is unique per item
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.body)
                                    .lineLimit(1)
                                Text(item.ownerName)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            
                            Spacer()
                            
                            // Toggle - use displayName as unique key
                            Toggle("", isOn: Binding(
                                get: { selectedDisplayNames.contains(item.displayName) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedDisplayNames.insert(item.displayName)
                                    } else {
                                        selectedDisplayNames.remove(item.displayName)
                                    }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }
                        .padding(.vertical, 4)
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
            // Get all menu bar items
            let allItems = MenuBarItem.getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)
            
            print("[DroppyBarConfig] Raw items: \(allItems.count)")
            for item in allItems {
                print("  - \(item.ownerName) (bundle: \(item.owningApplication?.bundleIdentifier ?? "nil"))")
            }
            
            // Filter: each item is unique by windowID, don't collapse by ownerName!
            menuBarItems = allItems.filter { item in
                // Skip Droppy's own items
                let isDroppyItem = item.ownerName.contains("Droppy") || 
                                   item.title?.contains("Droppy") == true ||
                                   item.bundleIdentifier?.contains("iordv.Droppy") == true
                guard !isDroppyItem else { return false }
                
                // Skip items with negative X (hidden off-screen)
                guard item.frame.minX >= 0 else { return false }
                
                // Skip items that are too wide (likely not menu bar icons)
                guard item.frame.width < 200 else { return false }
                
                return true
            }
            
            // Load current selection - now using displayName
            selectedDisplayNames = itemStore.enabledDisplayNames
            
            isLoading = false
            print("[DroppyBarConfig] Showing \(menuBarItems.count) individual items")
        }
    }
    
    private func saveSelection() {
        print("[DroppyBarConfig] Saving \(selectedDisplayNames.count) items: \(selectedDisplayNames)")
        
        // Clear existing items
        itemStore.clearAll()
        
        // Add selected items - match by displayName
        var position = 0
        for item in menuBarItems where selectedDisplayNames.contains(item.displayName) {
            let droppyItem = DroppyBarItem(
                ownerName: item.ownerName,
                bundleIdentifier: item.owningApplication?.bundleIdentifier,
                displayName: item.displayName,
                position: position
            )
            itemStore.addItem(droppyItem)
            position += 1
        }
    }
}

#Preview {
    DroppyBarConfigView(onDismiss: {})
}
