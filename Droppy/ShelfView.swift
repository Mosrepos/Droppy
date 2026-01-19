//
//  ShelfView.swift
//  Droppy
//
//  Created by Jordy Spruit on 02/01/2026.
//

import SwiftUI

/// The main shelf view that displays dropped items and handles new drops
struct ShelfView: View {
    /// Reference to the app state
    @Bindable var state: DroppyState
    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground
    
    var body: some View {
        ZStack {
            if state.items.isEmpty {
                emptyStateView
            } else {
                itemsScrollView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(useTransparentBackground ? AnyShapeStyle(.ultraThinMaterial) : AnyShapeStyle(Color.black))
        .dropDestination(for: URL.self) { urls, _ in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                state.addItems(from: urls)
            }
            return true
        }
    }
    
    private var itemsScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(state.items) { item in
                    DroppedItemView(
                        item: item,
                        isSelected: state.selectedItems.contains(item.id),
                        onSelect: {
                            state.toggleSelection(item)
                        },
                        onRemove: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                state.removeItem(item)
                            }
                        }
                    )
                    .padding(.vertical, 12)
                    .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 10)
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(NSColor.labelColor).opacity(0.05))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "tray.and.arrow.down")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 4) {
                Text("Shelf is empty")
                    .font(.system(size: 13, weight: .semibold))
                
                Text("Drop files or folders here")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ShelfView(state: DroppyState.shared)
        .frame(width: 400, height: 150)
}
