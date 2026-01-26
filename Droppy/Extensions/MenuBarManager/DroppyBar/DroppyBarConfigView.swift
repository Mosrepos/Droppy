//
//  DroppyBarConfigView.swift
//  Droppy
//
//  Configuration view for selecting which apps to show in Droppy Bar.
//

import SwiftUI
import AppKit

/// Configuration sheet for Droppy Bar
struct DroppyBarConfigView: View {
    let onDismiss: () -> Void
    
    @State private var availableApps: [AvailableApp] = []
    @State private var selectedBundleIds: Set<String> = []
    
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
            Text("Select apps to show in the Droppy Bar. Only apps with active menu bar icons are listed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 8)
            
            // App list
            if availableApps.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading apps with menu bar icons...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(availableApps) { app in
                        HStack {
                            if let icon = app.icon {
                                Image(nsImage: icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "app.dashed")
                                    .frame(width: 24, height: 24)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.body)
                                Text(app.bundleId)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { selectedBundleIds.contains(app.bundleId) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedBundleIds.insert(app.bundleId)
                                    } else {
                                        selectedBundleIds.remove(app.bundleId)
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
        .frame(width: 400, height: 500)
        .onAppear {
            loadAvailableApps()
            loadCurrentSelection()
        }
    }
    
    private func loadAvailableApps() {
        Task { @MainActor in
            // Get all menu bar items
            let menuBarItems = MenuBarItem.getMenuBarItems(onScreenOnly: false, activeSpaceOnly: true)
            
            // Group by bundle ID and create unique list
            var appMap: [String: AvailableApp] = [:]
            
            for item in menuBarItems {
                guard let app = item.owningApplication,
                      let bundleId = app.bundleIdentifier else { continue }
                
                // Skip if already added
                guard appMap[bundleId] == nil else { continue }
                
                // Skip system apps
                if ["com.apple.controlcenter", "com.apple.Spotlight", "com.apple.dock"].contains(bundleId) {
                    continue
                }
                
                appMap[bundleId] = AvailableApp(
                    bundleId: bundleId,
                    name: app.localizedName ?? item.ownerName,
                    icon: app.icon
                )
            }
            
            availableApps = appMap.values.sorted { $0.name < $1.name }
        }
    }
    
    private func loadCurrentSelection() {
        selectedBundleIds = itemStore.enabledBundleIds
    }
    
    private func saveSelection() {
        // Clear existing items
        itemStore.clearAll()
        
        // Add selected items
        for (index, app) in availableApps.enumerated() where selectedBundleIds.contains(app.bundleId) {
            let item = DroppyBarItem(bundleIdentifier: app.bundleId, displayName: app.name, position: index)
            itemStore.addItem(item)
        }
    }
}

/// Represents an app available for configuration
struct AvailableApp: Identifiable {
    let bundleId: String
    let name: String
    let icon: NSImage?
    
    var id: String { bundleId }
}

#Preview {
    DroppyBarConfigView(onDismiss: {})
}
