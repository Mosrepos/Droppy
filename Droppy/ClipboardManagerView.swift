import SwiftUI
import UniformTypeIdentifiers
import LinkPresentation
import Quartz
import AVKit

// MARK: - Quick Look Data Source for Clipboard Images
class QuickLookDataSource: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookDataSource()
    var urls: [URL] = []
    
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }
    
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}

/// Avoids SwiftUI's VideoPlayer metadata path by hosting AVPlayerView directly.
private struct SafeVideoPreview: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: ()) {
        nsView.player?.pause()
        nsView.player = nil
    }
}

struct ClipboardManagerView: View {
    private enum TrafficLightKind {
        case close
        case minimize
        case zoom
    }

    @ObservedObject var manager = ClipboardManager.shared
    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground
    @AppStorage(AppPreferenceKey.clipboardAutoFocusSearch) private var autoFocusSearch = PreferenceDefault.clipboardAutoFocusSearch
    @AppStorage(AppPreferenceKey.clipboardTagsEnabled) private var tagsEnabled = PreferenceDefault.clipboardTagsEnabled
    @State private var selectedItems: Set<UUID> = []
    @State private var isResetHovering = false
    @State private var scrollProxy: ScrollViewProxy?

    
    @State private var isSearchHovering = false
    @State private var dashPhase: CGFloat = 0
    
    // Search State
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @FocusState private var isSearchFocused: Bool
    
    // Pending selection: When user clicks during search, capture ID here to enforce after list rebuild
    @State private var pendingSelectionId: UUID? = nil
    
    // Range selection anchor for Shift+Click
    @State private var lastClickedItemId: UUID?
    
    // Rename popover state (tooltip style like ToDo edit)
    @State private var renamingItemId: UUID?
    @State private var renamingText = ""
    
    // Tag Filter State
    @State private var selectedTagFilter: UUID? = nil  // nil = show all
    @State private var isTagPopoverVisible = false
    @State private var showTagManagement = false
    @State private var showClearAllConfirmation = false
    @State private var topBarTextEditingItemID: UUID?
    @State private var topBarTextEditingContent = ""
    @State private var hoveredTrafficLight: TrafficLightKind?
    @State private var suppressListAnimations = true
    
    // Cached sorted/filtered history (updated only when needed)
    @State private var cachedSortedHistory: [ClipboardItem] = []
    @State private var removingBackgroundItemIDs: Set<UUID> = []
    
    /// Helper to get selected items as array, respecting visual order
    private var selectedItemsArray: [ClipboardItem] {
        cachedSortedHistory.filter { selectedItems.contains($0.id) }
    }
    
    /// Alias for cached history (compatibility)
    private var sortedHistory: [ClipboardItem] {
        cachedSortedHistory
    }
    
    /// Flagged items (shown in 2-column grid at top)
    private var flaggedItems: [ClipboardItem] {
        cachedSortedHistory.filter { $0.isFlagged }
    }
    
    /// Non-flagged items (shown in regular list)
    private var nonFlaggedItems: [ClipboardItem] {
        cachedSortedHistory.filter { !$0.isFlagged }
    }

    private var singleSelectedItem: ClipboardItem? {
        guard selectedItemsArray.count == 1 else { return nil }
        return selectedItemsArray.first
    }

    /// Single selected image that can be opened in Screenshot Editor.
    private var selectedEditableImage: NSImage? {
        guard let item = singleSelectedItem,
              item.type == .image,
              let imageData = item.loadImageData() else {
            return nil
        }
        return NSImage(data: imageData)
    }

    // Actions passed from Controller
    var onPaste: (ClipboardItem) -> Void
    var onPasteItems: ([ClipboardItem]) -> Void  // Issue #154: Batch paste
    var onClose: () -> Void
    var onReset: () -> Void

    init(
        onPaste: @escaping (ClipboardItem) -> Void,
        onPasteItems: @escaping ([ClipboardItem]) -> Void,
        onClose: @escaping () -> Void,
        onReset: @escaping () -> Void
    ) {
        self.onPaste = onPaste
        self.onPasteItems = onPasteItems
        self.onClose = onClose
        self.onReset = onReset
        _cachedSortedHistory = State(
            initialValue: Self.computeSortedHistory(
                history: ClipboardManager.shared.history,
                searchText: "",
                tagFilter: nil
            )
        )
    }
    
    var body: some View {
        mainContentView
            .overlay(alignment: .bottom) {
                if !showTagManagement {
                    feedbackToastView
                }
            }
            .overlay { tagManagementOverlay }
            .onAppear { 
                updateSortedHistory()
                handleOnAppear() 
            }
            .onChange(of: manager.history) { _, new in 
                updateSortedHistory()
                handleHistoryChange(new) 
            }
            .onChange(of: searchText) { _, _ in
                updateSortedHistory()
            }
            .onChange(of: selectedTagFilter) { _, _ in
                updateSortedHistory()
            }
            .onChange(of: tagsEnabled) { _, enabled in
                if !enabled {
                    isTagPopoverVisible = false
                    selectedTagFilter = nil
                }
            }
            .onChange(of: showTagManagement) { _, showing in
                if showing {
                    isTagPopoverVisible = false
                }
            }
            .onChange(of: singleSelectedItem?.id) { _, selectedID in
                if topBarTextEditingItemID != selectedID {
                    topBarTextEditingItemID = nil
                    topBarTextEditingContent = ""
                }
            }
            // ENFORCE PENDING SELECTION: After sortedHistory changes, apply pending selection
            .onChange(of: cachedSortedHistory) { _, _ in
                if let pendingId = pendingSelectionId {
                    // Clear pending immediately to prevent re-triggering
                    pendingSelectionId = nil
                    // Force selection to ONLY the pending item
                    selectedItems = [pendingId]
                }
            }
            // Issue #33: onAppear might not fire if window is just hidden/shown (cached view)
            // Use custom notification from Controller to force reset every time window opens
            .onReceive(NotificationCenter.default.publisher(for: .clipboardWindowDidShow)) { _ in
                suppressListAnimations = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
                    suppressListAnimations = false
                }
                // Clear any pending selection on fresh window open
                pendingSelectionId = nil
                handleOnAppear()
            }
            .onReceive(NotificationCenter.default.publisher(for: .clipboardWindowDidHide)) { _ in
                suppressListAnimations = true
                pendingSelectionId = nil
                selectedItems.removeAll()
                topBarTextEditingItemID = nil
                topBarTextEditingContent = ""
            }
    }
    
    private var mainContentView: some View {
        HStack(spacing: 0) {
            clipboardLeftPanel

            VStack(spacing: 0) {
                clipboardTitleBar

                previewPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 12)
                    .padding(.leading, 12)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
            }
        }
        .droppyTransparentBackground(useTransparentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AdaptiveColors.overlayAuto(0.16), lineWidth: 1)
        )
        .frame(minWidth: 1040, maxWidth: .infinity, minHeight: 640, maxHeight: .infinity)
        .background(pasteShortcutButton)
        .background(navigationShortcutButtons)
        .confirmationDialog(
            "Clear all clipboard history?",
            isPresented: $showClearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                clearAllClipboardHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove all clipboard items.")
        }
    }

    @ViewBuilder
    private var tagManagementOverlay: some View {
        if showTagManagement {
            ZStack {
                Color.black.opacity(0.48)
                    .contentShape(Rectangle())
                    .onTapGesture { closeTagManagement() }

                TagManagementSheet(
                    manager: manager,
                    onDone: closeTagManagement
                )
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(DroppyAnimation.transition, value: showTagManagement)
        }
    }

    private var clipboardLeftPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            trafficLightsRow
                .padding(.top, 10)
                .padding(.horizontal, 12)

            entriesListView
        }
        .frame(width: 400)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .droppyTransparentFill(useTransparentBackground, fallback: AdaptiveColors.panelBackgroundAuto)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AdaptiveColors.overlayAuto(0.18), lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var clipboardTitleBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            Text("Clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.88))

            Spacer(minLength: 0)

            clipboardTitleBarTrailingAction
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            ZStack {
                ClipboardWindowDragView()
            }
        )
    }

    @ViewBuilder
    private var clipboardTitleBarTrailingAction: some View {
        if let image = selectedEditableImage {
            Button {
                ScreenshotEditorWindowController.shared.show(with: image)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Edit")
                }
            }
            .buttonStyle(DroppyAccentButtonStyle(color: AdaptiveColors.selectionBlueAuto, size: .small))
            .help("Edit in Screenshot Editor")
        } else if let selected = singleSelectedItem, selected.type == .text {
            let isEditingSelectedText = topBarTextEditingItemID == selected.id
            Button {
                if isEditingSelectedText {
                    manager.updateItemContent(selected, newContent: topBarTextEditingContent)
                    topBarTextEditingItemID = nil
                } else {
                    topBarTextEditingContent = selected.content ?? ""
                    topBarTextEditingItemID = selected.id
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isEditingSelectedText ? "checkmark" : "pencil")
                        .font(.system(size: 11, weight: .semibold))
                    Text(isEditingSelectedText ? "Save" : "Edit")
                }
            }
            .buttonStyle(DroppyAccentButtonStyle(color: isEditingSelectedText ? .green : AdaptiveColors.selectionBlueAuto, size: .small))
            .help(isEditingSelectedText ? "Save Text" : "Edit Text")
        }
    }

    private var trafficLightsRow: some View {
        HStack(spacing: 8) {
            trafficLightButton(
                kind: .close,
                color: Color(red: 1.0, green: 0.37, blue: 0.34),
                symbol: "xmark",
                action: onClose
            )
            trafficLightButton(
                kind: .minimize,
                color: Color(red: 1.0, green: 0.74, blue: 0.18),
                symbol: "minus",
                action: { NSApp.keyWindow?.miniaturize(nil) }
            )
            trafficLightButton(
                kind: .zoom,
                color: Color(red: 0.17, green: 0.82, blue: 0.33),
                symbol: "plus",
                action: { NSApp.keyWindow?.zoom(nil) }
            )

            Spacer()

            Button {
                guard tagsEnabled else { return }
                isTagPopoverVisible.toggle()
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "tag")
                    if selectedTagFilter != nil {
                        Circle()
                            .fill(manager.getTag(by: selectedTagFilter)?.color ?? .blue)
                            .frame(width: 6, height: 6)
                            .offset(x: 2, y: -2)
                    }
                }
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 28))
            .droppyPopover(isPresented: $isTagPopoverVisible, arrowEdge: .bottom) {
                TagFilterPopover(
                    selectedTagFilter: $selectedTagFilter,
                    showTagManagement: $showTagManagement,
                    manager: manager
                )
            }
            .disabled(!tagsEnabled)
            .opacity(tagsEnabled ? 1 : 0)
            .allowsHitTesting(tagsEnabled)
            .help("Filter by Tag")

            Button {
                withAnimation(DroppyAnimation.state) {
                    isSearchVisible.toggle()
                    if !isSearchVisible {
                        searchText = ""
                        isSearchFocused = false
                    } else {
                        isSearchFocused = true
                    }
                }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 28))
            .keyboardShortcut("f", modifiers: .command)
            .help("Search (⌘F)")

            Button(role: .destructive) {
                showClearAllConfirmation = true
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(DroppyCircleButtonStyle(size: 28))
            .disabled(manager.history.isEmpty)
            .help("Clear All")
        }
        .onHover { hovering in
            if !hovering {
                hoveredTrafficLight = nil
            }
        }
    }

    private func trafficLightButton(
        kind: TrafficLightKind,
        color: Color,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.2), lineWidth: 0.6)
                    )

                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.65))
                    .opacity(hoveredTrafficLight == nil ? 0 : 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredTrafficLight = hovering ? kind : nil
        }
    }
    
    private var pasteShortcutButton: some View {
        Button("") {
            // Issue #154: Use batch paste to avoid race conditions
            onPasteItems(selectedItemsArray)
        }
            .keyboardShortcut(.return, modifiers: []) // 1. Return -> Paste
            .keyboardShortcut(.return, modifiers: .command) // 2. Cmd+Return -> Paste (Bonus)
            .disabled(showTagManagement)
            .opacity(0)
    }
    
    @ViewBuilder
    private var navigationShortcutButtons: some View {
        VStack {
            Button("") { navigateSelection(direction: -1) }.keyboardShortcut(.upArrow, modifiers: [])
            Button("") { navigateSelection(direction: 1) }.keyboardShortcut(.downArrow, modifiers: [])
            Button("") { deleteSelectedItems() }.keyboardShortcut(.delete, modifiers: [])
            Button("") { deleteSelectedItems() }.keyboardShortcut(KeyEquivalent("\u{08}"), modifiers: []) // Backspace
            Button("") { deleteSelectedItems() }.keyboardShortcut("d", modifiers: .command) // Cmd+D
            
            // 5. Command+A -> Select All (always works)
            Button("") {
                selectedItems = Set(sortedHistory.map { $0.id })
            }.keyboardShortcut("a", modifiers: .command)
            
            // CONDITIONAL SHORTCUTS: Only register when NOT editing
            // This allows native Cmd+C, Cmd+V, Space to work in text fields
            if !manager.isEditingContent {
                // Command+C -> Copy Selected to Clipboard
                Button("") { copySelectedToClipboard() }.keyboardShortcut("c", modifiers: .command)
                
                // Command+V -> Paste Selected Items (Issue #154: Batch paste)
                Button("") {
                    onPasteItems(selectedItemsArray)
                }.keyboardShortcut("v", modifiers: .command)
                
                // Spacebar -> Quick Look for images
                Button("") { showQuickLookForSelected() }.keyboardShortcut(.space, modifiers: [])
                
                // Command+S -> Bulk Save selected items
                Button("") { bulkSaveSelectedItems() }.keyboardShortcut("s", modifiers: .command)
            }
        }
        .disabled(showTagManagement)
        .opacity(0)
        // Force SwiftUI to rebuild this view when editing state changes
        // This ensures keyboard shortcuts are properly registered/unregistered
        .id("shortcuts-\(manager.isEditingContent)")
    }

    private func closeTagManagement() {
        withAnimation(DroppyAnimation.transition) {
            showTagManagement = false
        }
    }
    
    private func handleOnAppear() {
        // Block if there's a pending selection - user's click takes priority
        if pendingSelectionId != nil {
            return
        }
        
        // Issue #33: Always highlight the last copied item (first in list), not the last selected item
        // Also reset search state when opening
        searchText = ""
        
        // Issue #43: Auto-focus search if enabled
        if autoFocusSearch {
            isSearchVisible = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        } else {
            isSearchVisible = false
            isSearchFocused = false
        }
        
        // Logic change: "Last Copied" is the chronologically newest item.
        // Since manager.history is pre-sorted with Favorites at the top, we must search by date.
        if let lastCopied = manager.history.max(by: { $0.date < $1.date }) {
            selectedItems = [lastCopied.id]
            // Scroll to it in case it's below favorites
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if suppressListAnimations {
                    scrollProxy?.scrollTo(lastCopied.id, anchor: .center)
                } else {
                    withAnimation(DroppyAnimation.transition) {
                        scrollProxy?.scrollTo(lastCopied.id, anchor: .center)
                    }
                }
            }
        } else {
            selectedItems = []
        }
    }

    private static func computeSortedHistory(
        history: [ClipboardItem],
        searchText: String,
        tagFilter: UUID?
    ) -> [ClipboardItem] {
        var filtered: [ClipboardItem]

        if let tagId = tagFilter {
            filtered = history.filter { $0.tagId == tagId }
        } else {
            filtered = history
        }

        if !searchText.isEmpty {
            filtered = filtered.filter { item in
                let contentPreview = String((item.content ?? "").prefix(10000))
                return item.title.localizedCaseInsensitiveContains(searchText) ||
                    contentPreview.localizedCaseInsensitiveContains(searchText) ||
                    (item.sourceApp ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }

        let flagged = filtered.filter { $0.isFlagged }
        let favorites = filtered.filter { $0.isFavorite && !$0.isFlagged }
        let others = filtered.filter { !$0.isFavorite && !$0.isFlagged }
        return flagged + favorites + others
    }

    private func updateSortedHistory() {
        cachedSortedHistory = Self.computeSortedHistory(
            history: manager.history,
            searchText: searchText,
            tagFilter: selectedTagFilter
        )
    }
    
    private func handleHistoryChange(_ new: [ClipboardItem]) {
        // Block if there's a pending selection - user's click takes priority
        if pendingSelectionId != nil {
            // Still need to prune deleted items, but don't add any
            selectedItems = selectedItems.filter { id in new.contains { $0.id == id } }
            return
        }
        
        // Remove any selected items that no longer exist
        selectedItems = selectedItems.filter { id in new.contains { $0.id == id } }
        
        // Re-calculate sorted history based on the new data
        let currentSorted = new.filter { $0.isFavorite } + new.filter { !$0.isFavorite }
        
        if selectedItems.isEmpty, let first = currentSorted.first {
            selectedItems.insert(first.id)
        }
    }
    
    @ViewBuilder
    private var feedbackToastView: some View {
        if manager.showPasteFeedback {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Copied to Clipboard & Pasting…")
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(useTransparentBackground ? AnyShapeStyle(.ultraThinMaterial) : AdaptiveColors.panelBackgroundOpaqueStyle)
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.xl, style: .continuous)
                    .stroke(AdaptiveColors.overlayAuto(0.1), lineWidth: 1)
            )
            .droppyCardShadow()
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
    
    private func navigateSelection(direction: Int) {
        // Find current "anchor" item for navigation using VISUAL sorted order
        guard let firstSelected = selectedItems.first,
              let currentItem = sortedHistory.first(where: { $0.id == firstSelected }),
              let index = sortedHistory.firstIndex(where: { $0.id == currentItem.id }) else {
            if let first = sortedHistory.first {
                withAnimation(DroppyAnimation.hover) {
                    selectedItems = [first.id]
                }
                withAnimation(DroppyAnimation.easeInOut) {
                    scrollProxy?.scrollTo(first.id, anchor: .center)
                }
            }
            return
        }
        
        let newIndex = index + direction
        if newIndex >= 0 && newIndex < sortedHistory.count {
            let newId = sortedHistory[newIndex].id
            // Silky smooth scrolling - instant selection, fluid scroll
            selectedItems = [newId]
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.22)) {
                scrollProxy?.scrollTo(newId, anchor: .center)
            }
        }
    }
    
    private func deleteSelectedItems() {
        guard !selectedItems.isEmpty else { return }
        
        // Find next item to select after deletion
        let itemsToDelete = selectedItemsArray
        let remainingItems = manager.history.filter { !selectedItems.contains($0.id) }
        
        for item in itemsToDelete {
            manager.delete(item: item)
        }
        if let first = remainingItems.first {
            selectedItems = [first.id]
        } else {
            selectedItems = []
        }
    }

    private func clearAllClipboardHistory() {
        manager.clearAllHistory()
        selectedItems = []
        pendingSelectionId = nil
        lastClickedItemId = nil
    }
    
    /// Show Quick Look preview for selected image items
    private func showQuickLookForSelected() {
        // Get image items that have file URLs
        let imageItems = selectedItemsArray.filter { $0.type == .image }
        guard !imageItems.isEmpty else { return }
        
        // Create temp files for Quick Look
        var urls: [URL] = []
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DroppyQuickLook", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        for item in imageItems {
            if let data = item.loadImageData() {
                let fileName = "\(item.id.uuidString).png"
                let fileURL = tempDir.appendingPathComponent(fileName)
                try? data.write(to: fileURL)
                urls.append(fileURL)
            }
        }
        
        guard !urls.isEmpty else { return }
        
        // Show Quick Look panel
        if let panel = QLPreviewPanel.shared() {
            QuickLookDataSource.shared.urls = urls
            panel.dataSource = QuickLookDataSource.shared
            panel.delegate = QuickLookDataSource.shared
            panel.makeKeyAndOrderFront(nil)
            panel.reloadData()
        }
    }
    
    /// Bulk save all selected items to Downloads folder
    private func bulkSaveSelectedItems() {
        guard !selectedItems.isEmpty else { return }
        
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        var savedCount = 0
        
        for item in selectedItemsArray {
            let fileName: String
            let fileExtension: String
            let data: Data?
            
            switch item.type {
            case .image:
                fileName = item.customTitle ?? "Image_\(Int(Date().timeIntervalSince1970))_\(savedCount)"
                fileExtension = "png"
                if let imgData = item.loadImageData(),
                   let nsImage = NSImage(data: imgData),
                   let tiffData = nsImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    data = pngData
                } else {
                    data = nil
                }
            case .text:
                fileName = item.customTitle ?? "Text_\(Int(Date().timeIntervalSince1970))_\(savedCount)"
                fileExtension = "txt"
                data = item.content?.data(using: .utf8)
            case .url:
                fileName = item.customTitle ?? "Link_\(Int(Date().timeIntervalSince1970))_\(savedCount)"
                fileExtension = "txt"
                data = item.content?.data(using: .utf8)
            case .file:
                // For files, copy the original
                if let path = item.content {
                    let sourceURL = URL(fileURLWithPath: path)
                    var destURL = downloads.appendingPathComponent(sourceURL.lastPathComponent)
                    // Handle collision
                    var counter = 1
                    while FileManager.default.fileExists(atPath: destURL.path) {
                        let name = sourceURL.deletingPathExtension().lastPathComponent
                        let ext = sourceURL.pathExtension
                        destURL = downloads.appendingPathComponent("\(name)_\(counter).\(ext)")
                        counter += 1
                    }
                    try? FileManager.default.copyItem(at: sourceURL, to: destURL)
                    savedCount += 1
                }
                continue
            case .color:
                continue
            }
            
            guard let saveData = data else { continue }
            
            var destURL = downloads.appendingPathComponent(fileName).appendingPathExtension(fileExtension)
            // Handle collision
            var counter = 1
            while FileManager.default.fileExists(atPath: destURL.path) {
                destURL = downloads.appendingPathComponent("\(fileName)_\(counter)").appendingPathExtension(fileExtension)
                counter += 1
            }
            
            do {
                try saveData.write(to: destURL)
                savedCount += 1
            } catch {
                print("Failed to save: \(error)")
            }
        }
        
        if savedCount > 0 {
            // Show feedback
            print("📁 Saved \(savedCount) item(s) to Downloads")
        }
    }
    
    var entriesListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Search Bar - Styled exactly like RenameTextField from FloatingBasketView
            if isSearchVisible {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))
                    
                    TextField("Search history…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($isSearchFocused)
                        .frame(maxWidth: .infinity)
                    
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 20))
                    .opacity(searchText.isEmpty ? 0 : 1)
                    .disabled(searchText.isEmpty)
                }
                .droppyTextInputChrome(
                    cornerRadius: DroppyRadius.large,
                    horizontalPadding: 10,
                    verticalPadding: 8
                )
                .padding(.horizontal, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if !manager.hasAccessibilityPermission {
                accessibilityWarning
            }
            
            if manager.history.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "scissors")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Clipboard is empty")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            // Flagged Items Section (2-column grid)
                            if !flaggedItems.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Section header
                                    HStack(spacing: 6) {
                                        Image(systemName: "flag.fill")
                                            .foregroundStyle(.red)
                                        Text("Important")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 4)
                                    
                                    // 2-column grid for flagged items
                                    LazyVGrid(columns: [
                                        GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)
                                    ], spacing: 8) {
                                        ForEach(flaggedItems) { item in
                                            flaggedGridItem(for: item)
                                        }
                                    }
                                }
                                .padding(.bottom, 8)
                                
                                // Divider between flagged and regular items
                                if !nonFlaggedItems.isEmpty {
                                    Divider()
                                        .padding(.horizontal, 20)
                                }
                            }
                            
                            // Regular Items List
                            LazyVStack(spacing: 8) {
                                ForEach(nonFlaggedItems) { item in
                                DraggableArea(
                                    items: {
                                        // If this item is selected, drag all selected
                                        if selectedItems.contains(item.id) {
                                            return selectedItemsArray.flatMap { clipboardItemToPasteboardWritings($0) }
                                        }
                                        return clipboardItemToPasteboardWritings(item)
                                    },
                                    onTap: { modifiers in
                                        // 1. Handle Selection First (Priority)
                                        if modifiers.contains(.shift) {
                                            // Shift+Click: range selection
                                            if let anchorId = lastClickedItemId,
                                               let anchorIndex = sortedHistory.firstIndex(where: { $0.id == anchorId }),
                                               let clickedIndex = sortedHistory.firstIndex(where: { $0.id == item.id }) {
                                                let range = min(anchorIndex, clickedIndex)...max(anchorIndex, clickedIndex)
                                                for i in range {
                                                    selectedItems.insert(sortedHistory[i].id)
                                                }
                                            } else {
                                                selectedItems = [item.id]
                                                lastClickedItemId = item.id
                                            }
                                        } else if modifiers.contains(.command) {
                                            // Cmd+Click: toggle selection
                                            if selectedItems.contains(item.id) {
                                                selectedItems.remove(item.id)
                                            } else {
                                                selectedItems.insert(item.id)
                                            }
                                            lastClickedItemId = item.id
                                        } else {
                                            // Normal click: select only this
                                            selectedItems = [item.id]
                                            lastClickedItemId = item.id
                                        }
                                        
                                        // 2. Then Hide Search if active
                                        // Doing this after selection ensures the selection state is captured 
                                        // before the list rebuilds (due to searchText change)
                                        if isSearchVisible {
                                            // Capture the clicked item ID BEFORE closing search
                                            // This will be enforced by onChange(cachedSortedHistory) after list rebuilds
                                            pendingSelectionId = item.id
                                            
                                            // Close search - this triggers list rebuild
                                            withAnimation(DroppyAnimation.state) {
                                                isSearchVisible = false
                                                searchText = ""
                                                isSearchFocused = false
                                            }
                                        }
                                    },
                                    onDoubleClick: {
                                        renamingText = item.title
                                        renamingItemId = item.id
                                    },
                                    onRightClick: {
                                        // CRITICAL: Defer selection to AFTER menu opens to avoid view recreation lag
                                        // The view recreation (due to .id modifier) would block the menu if done synchronously
                                        DispatchQueue.main.async {
                                            if !selectedItems.contains(item.id) {
                                                selectedItems = [item.id]
                                            }
                                        }
                                    },
                                    // Force DraggableArea to update when selection changes
                                    selectionSignature: selectedItems.contains(item.id) ? 1 : 0
                                ) {
                                    ClipboardItemRow(
                                        item: item, 
                                        isSelected: selectedItems.contains(item.id),
                                        isRemovingBackground: removingBackgroundItemIDs.contains(item.id),
                                        renamingItemId: $renamingItemId,
                                        renamingText: $renamingText,
                                        onRename: { newName in
                                            manager.rename(item: item, to: newName)
                                            updateSortedHistory()
                                        }
                                    )
                                    .frame(width: 360)  // Fixed width to prevent text expansion
                                }
                                // Include selection + item status in identity so DraggableArea rows
                                // always refresh their status badges after favorite/flag toggles.
                                .id("\(item.id.uuidString)-\(selectedItems.contains(item.id) ? "sel" : "unsel")-\(item.isFavorite ? "fav" : "nofav")-\(item.isFlagged ? "flag" : "noflag")")
                                .contextMenu {
                                    if selectedItems.count > 1 {
                                        // Multi-select context menu
                                        Button {
                                            for item in selectedItemsArray {
                                                onPaste(item)
                                            }
                                        } label: {
                                            Label("Paste All (\(selectedItems.count))", systemImage: "doc.on.clipboard")
                                        }
                                        Button {
                                            copySelectedToClipboard()
                                        } label: {
                                            Label("Copy All (\(selectedItems.count))", systemImage: "doc.on.doc")
                                        }
                                        Button {
                                            bulkSaveSelectedItems()
                                        } label: {
                                            Label("Save All (\(selectedItems.count))", systemImage: "square.and.arrow.down")
                                        }
                                        Divider()
                                        Button(role: .destructive) {
                                            deleteSelectedItems()
                                        } label: {
                                            Label("Delete \(selectedItems.count) Items", systemImage: "trash")
                                        }
                                    } else {
                                        // Single item context menu
                                        Button { onPaste(item) } label: {
                                            Label("Paste", systemImage: "doc.on.clipboard")
                                        }
                                        Button {
                                            let willBeFavorite = !item.isFavorite
                                            manager.toggleFavorite(item)
                                            // Scroll to the item after it moves to favorites section
                                            if willBeFavorite {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                    withAnimation(DroppyAnimation.transition) {
                                                        scrollProxy?.scrollTo(item.id, anchor: .top)
                                                    }
                                                }
                                            }
                                        } label: {
                                            Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.slash" : "star")
                                        }
                                        Button {
                                            let willBeFlagged = !item.isFlagged
                                            manager.toggleFlag(item)
                                            // Scroll to the item after it moves to flagged section
                                            if willBeFlagged {
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                                    withAnimation(DroppyAnimation.transition) {
                                                        scrollProxy?.scrollTo(item.id, anchor: .top)
                                                    }
                                                }
                                            }
                                        } label: {
                                            Label(item.isFlagged ? "Remove Flag" : "Flag as Important", systemImage: item.isFlagged ? "flag.slash" : "flag.fill")
                                        }
                                        
                                        // Tag submenu (only if tags enabled)
                                        if tagsEnabled {
                                            Menu {
                                                // Show all available tags
                                                ForEach(manager.tags) { tag in
                                                    Button {
                                                        manager.assignTag(tag, to: item)
                                                    } label: {
                                                        HStack {
                                                            Circle()
                                                                .fill(tag.color)
                                                                .frame(width: 8, height: 8)
                                                            Text(tag.name)
                                                            if item.tagId == tag.id {
                                                                Image(systemName: "checkmark")
                                                            }
                                                        }
                                                    }
                                                }
                                                
                                                if !manager.tags.isEmpty && item.tagId != nil {
                                                    Divider()
                                                    Button(role: .destructive) {
                                                        manager.removeTagFromItem(item)
                                                    } label: {
                                                        Label("Remove Tag", systemImage: "tag.slash")
                                                    }
                                                }
                                                
                                                if manager.tags.isEmpty {
                                                    Text("No tags yet - create one in tag settings")
                                                        .foregroundStyle(.secondary)
                                                }
                                            } label: {
                                                Label("Tag", systemImage: "tag")
                                            }
                                        }
                                        
                                        Divider()
                                        
                                        // Move to Shelf/Basket
                                        Button {
                                            moveItemToShelf(item)
                                        } label: {
                                            Label("Move to Shelf", systemImage: "arrow.up.to.line")
                                        }
                                        Button {
                                            moveItemToBasket(item)
                                        } label: {
                                            Label("Move to Basket", systemImage: "tray.and.arrow.down")
                                        }

                                        if item.type == .image {
                                            if !ExtensionType.aiBackgroundRemoval.isRemoved && AIInstallManager.shared.isInstalled {
                                                let isRemovingBackground = removingBackgroundItemIDs.contains(item.id)
                                                Button {
                                                    removeBackgroundFromClipboardItem(item)
                                                } label: {
                                                    Label(
                                                        isRemovingBackground ? "Removing Background..." : "Remove Background",
                                                        systemImage: "person.and.background.dotted"
                                                    )
                                                }
                                                .disabled(isRemovingBackground)
                                            } else {
                                                Button {
                                                    // No action - informational only.
                                                } label: {
                                                    Label("Remove Background (Settings > Extensions)", systemImage: "person.and.background.dotted")
                                                }
                                                .disabled(true)
                                            }
                                        }
                                        
                                        Divider()
                                        Button {
                                            renamingText = item.title
                                            renamingItemId = item.id
                                        } label: {
                                            Label("Rename", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            manager.delete(item: item)
                                            selectedItems.remove(item.id)
                                            if selectedItems.isEmpty, let first = manager.history.first {
                                                selectedItems.insert(first.id)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        } // Close LazyVStack
                        } // Close VStack
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        // Animation for list changes (favorites, add/remove)
                        // PERFORMANCE: ID-only Hashable makes this comparison fast
                        .animation(suppressListAnimations ? nil : DroppyAnimation.listChange, value: sortedHistory)
                    }
                    .onAppear {
                        scrollProxy = proxy
                    }
                }
            } // Close else

        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity) // Sidebar takes full height, but width fixed
    }
    
    /// Compact grid item for flagged entries
    @ViewBuilder
    private func flaggedGridItem(for item: ClipboardItem) -> some View {
        FlaggedGridItemView(
            item: item,
            isSelected: selectedItems.contains(item.id),
            onTap: { selectedItems = [item.id] },
            onPaste: { onPaste(item) },
            onRemoveBackground: { removeBackgroundFromClipboardItem(item) },
            isRemovingBackground: removingBackgroundItemIDs.contains(item.id),
            manager: manager
        )
        .id(item.id)
    }
    
    /// Icon for clipboard item type
    @ViewBuilder
    private func clipboardItemIcon(for item: ClipboardItem) -> some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.text")
        case .image:
            Image(systemName: "photo")
        case .file:
            Image(systemName: "doc")
        case .url:
            Image(systemName: "link")
        case .color:
            Image(systemName: "paintpalette")
        }
    }
    
    var accessibilityWarning: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                Text("Accessibility Needed")
                    .fontWeight(.bold)
            }
            .font(.caption)
            
            Text("Droppy needs permission to paste into other apps.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            
            Button(action: openAccessibilitySettings) {
                Text("Open Settings")
            }
            .buttonStyle(DroppyAccentButtonStyle(color: .orange, size: .small))
        }
        .padding(DroppySpacing.md)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 20)
    }
    
    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
    
    /// Converts a ClipboardItem to a temp file URL for drag operations
    /// This ensures dragged items can be dropped as actual files
    private func clipboardItemToPasteboardWritings(_ item: ClipboardItem) -> [NSPasteboardWriting] {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DroppyClipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // Use a short unique suffix from UUID to prevent filename collisions when
        // multiple items with the same title are dragged together
        let uniqueSuffix = String(item.id.uuidString.prefix(8))
        
        switch item.type {
        case .text:
            if let content = item.content {
                // Create a .txt file with unique suffix
                let fileName = sanitizeFileName(item.title) + "_\(uniqueSuffix).txt"
                let fileURL = tempDir.appendingPathComponent(fileName)
                do {
                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                    return [fileURL as NSURL]
                } catch {
                    return [content as NSString]
                }
            }
        case .url:
            if let content = item.content {
                // Create a .webloc file for URLs with unique suffix
                let fileName = sanitizeFileName(item.title) + "_\(uniqueSuffix).webloc"
                let fileURL = tempDir.appendingPathComponent(fileName)
                let plist = ["URL": content]
                do {
                    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                    try data.write(to: fileURL)
                    return [fileURL as NSURL]
                } catch {
                    return [content as NSString]
                }
            }
        case .file:
            if let path = item.content {
                return [URL(fileURLWithPath: path) as NSURL]
            }
        case .image:
            if let data = item.loadImageData() {
                // Determine format and create appropriate file with unique suffix
                let fileName = sanitizeFileName(item.title) + "_\(uniqueSuffix)"
                let fileURL: URL
                
                // Check if it's PNG or use PNG as default
                if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                    fileURL = tempDir.appendingPathComponent(fileName + ".png")
                } else if data.starts(with: [0xFF, 0xD8, 0xFF]) {
                    fileURL = tempDir.appendingPathComponent(fileName + ".jpg")
                } else {
                    // Convert to PNG for unknown formats
                    fileURL = tempDir.appendingPathComponent(fileName + ".png")
                }
                
                do {
                    try data.write(to: fileURL)
                    return [fileURL as NSURL]
                } catch {
                    if let image = NSImage(data: data) {
                        return [image]
                    }
                }
            }
        case .color:
            break
        }
        return []
    }
    
    /// Sanitize filename for safe filesystem use
    private func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        var sanitized = name.components(separatedBy: invalid).joined(separator: "_")
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty { sanitized = "clipboard_item" }
        if sanitized.count > 50 { sanitized = String(sanitized.prefix(50)) }
        return sanitized
    }
    
    /// Copy all selected items to system clipboard (Issue #154: Fixed batch writes)
    private func copySelectedToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        
        var strings: [String] = []
        var urls: [URL] = []
        var images: [NSImage] = []  // Collect images for batch write
        
        for item in selectedItemsArray {
            switch item.type {
            case .text, .url:
                if let content = item.content {
                    strings.append(content)
                }
            case .file:
                if let path = item.content {
                    urls.append(URL(fileURLWithPath: path))
                }
            case .image:
                // Collect images instead of writing individually
                if let data = item.loadImageData(), let image = NSImage(data: data) {
                    images.append(image)
                }
            case .color:
                break
            }
        }
        
        // Write all content types in batches
        if !strings.isEmpty {
            pasteboard.setString(strings.joined(separator: "\n"), forType: .string)
        }
        if !urls.isEmpty {
            pasteboard.writeObjects(urls as [NSURL])
        }
        if !images.isEmpty {
            pasteboard.writeObjects(images)
        }
    }
    
    /// Moves clipboard item to the Floating Basket
    private func moveItemToBasket(_ item: ClipboardItem) {
        guard let fileURL = clipboardItemToTempFile(item) else { return }
        let droppedItem = DroppedItem(url: fileURL, isTemporary: true)
        FloatingBasketWindowController.addDroppedItemFromExternalSource(droppedItem)
    }
    
    /// Moves clipboard item to the Shelf
    private func moveItemToShelf(_ item: ClipboardItem) {
        guard let fileURL = clipboardItemToTempFile(item) else { return }
        let droppedItem = DroppedItem(url: fileURL, isTemporary: true)
        DroppyState.shared.addItem(droppedItem)
    }

    private func removeBackgroundFromClipboardItem(_ item: ClipboardItem) {
        guard item.type == .image else { return }
        guard !ExtensionType.aiBackgroundRemoval.isRemoved else { return }
        guard AIInstallManager.shared.isInstalled else { return }
        guard !removingBackgroundItemIDs.contains(item.id) else { return }

        removingBackgroundItemIDs.insert(item.id)

        Task {
            await Task.yield()
            do {
                let (inputURL, cleanupInputURL) = try makeBackgroundRemovalInput(for: item)
                defer {
                    if cleanupInputURL {
                        try? FileManager.default.removeItem(at: inputURL)
                    }
                }

                let outputURL = try await BackgroundRemovalManager.shared.removeBackground(from: inputURL)
                defer { try? FileManager.default.removeItem(at: outputURL) }

                let outputData = try Data(contentsOf: outputURL)

                await MainActor.run {
                    if let newItem = manager.addGeneratedImageToHistory(outputData, basedOn: item) {
                        selectedItems = [newItem.id]
                    }
                    removingBackgroundItemIDs.remove(item.id)
                }
            } catch {
                await MainActor.run {
                    removingBackgroundItemIDs.remove(item.id)
                    HapticFeedback.error()
                }
                await DroppyAlertController.shared.showError(
                    title: "Background Removal Failed",
                    message: error.localizedDescription
                )
            }
        }
    }

    private func makeBackgroundRemovalInput(for item: ClipboardItem) throws -> (URL, Bool) {
        if let sourceURL = item.getImageFileURL(),
           FileManager.default.fileExists(atPath: sourceURL.path) {
            return (sourceURL, false)
        }

        guard let imageData = item.loadImageData() else {
            throw NSError(
                domain: "ClipboardBackgroundRemoval",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to load image data from clipboard item."]
            )
        }

        let workingDirectory = manager.imagesDirectory.appendingPathComponent("bg-removal-work", isDirectory: true)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        let fileURL = workingDirectory.appendingPathComponent("bg_input_\(item.id.uuidString).png")
        try imageData.write(to: fileURL, options: .atomic)
        return (fileURL, true)
    }
    
    /// Converts a ClipboardItem to a temp file and returns its URL
    private func clipboardItemToTempFile(_ item: ClipboardItem) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DroppyClipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let uniqueSuffix = String(item.id.uuidString.prefix(8))
        
        switch item.type {
        case .text:
            if let content = item.content {
                let fileName = sanitizeFileName(item.title) + "_\(uniqueSuffix).txt"
                let fileURL = tempDir.appendingPathComponent(fileName)
                do {
                    try content.write(to: fileURL, atomically: true, encoding: .utf8)
                    return fileURL
                } catch { return nil }
            }
        case .url:
            if let content = item.content {
                let fileName = sanitizeFileName(item.title) + "_\(uniqueSuffix).webloc"
                let fileURL = tempDir.appendingPathComponent(fileName)
                let plist = ["URL": content]
                do {
                    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                    try data.write(to: fileURL)
                    return fileURL
                } catch { return nil }
            }
        case .file:
            if let path = item.content {
                return URL(fileURLWithPath: path)
            }
        case .image:
            if let data = item.loadImageData() {
                let fileName = sanitizeFileName(item.title) + "_\(uniqueSuffix)"
                let fileURL: URL
                
                if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
                    fileURL = tempDir.appendingPathComponent(fileName + ".png")
                } else if data.starts(with: [0xFF, 0xD8, 0xFF]) {
                    fileURL = tempDir.appendingPathComponent(fileName + ".jpg")
                } else {
                    fileURL = tempDir.appendingPathComponent(fileName + ".png")
                }
                
                do {
                    try data.write(to: fileURL)
                    return fileURL
                } catch { return nil }
            }
        case .color:
            return nil
        }
        return nil
    }
    
    var previewPane: some View {
        VStack(spacing: 0) {
            if selectedItems.count > 1 {
                // Multi-select stacked preview
                MultiSelectPreviewView(
                    items: selectedItemsArray,
                    onPasteAll: {
                        for item in selectedItemsArray {
                            onPaste(item)
                        }
                    },
                    onCopyAll: copySelectedToClipboard,
                    onSaveAll: bulkSaveSelectedItems,
                    onDeleteAll: deleteSelectedItems
                )
            } else if let firstId = selectedItems.first,
                      let item = manager.history.first(where: { $0.id == firstId }) {
                ClipboardPreviewView(
                    item: item, 
                    scrollProxy: scrollProxy,
                    showsPrimaryActionsInFooter: true,
                    topBarTextEditingItemID: $topBarTextEditingItemID,
                    topBarTextEditingContent: $topBarTextEditingContent,
                    onRemoveBackground: { removeBackgroundFromClipboardItem(item) },
                    isRemovingBackground: removingBackgroundItemIDs.contains(item.id),
                    onPaste: { onPaste(item) },
                    onDelete: { deleteSelectedItems() }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Select an item to preview")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(minWidth: 504, maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ClipboardWindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> ClipboardWindowDraggableView {
        ClipboardWindowDraggableView()
    }

    func updateNSView(_ nsView: ClipboardWindowDraggableView, context: Context) {}
}

private final class ClipboardWindowDraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        window.performDrag(with: event)
    }
}

// MARK: - Flagged Grid Item View
struct FlaggedGridItemView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onTap: () -> Void
    let onPaste: () -> Void
    let onRemoveBackground: () -> Void
    let isRemovingBackground: Bool
    @ObservedObject var manager: ClipboardManager
    
    @State private var isHovering = false
    @State private var cachedThumbnail: NSImage? // Async-loaded thumbnail
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                // Icon/Thumbnail - squircle like ClipboardItemRow
                ZStack {
                    RoundedRectangle(cornerRadius: DroppyRadius.sm, style: .continuous)
                        .fill(AdaptiveColors.overlayAuto(0.1))
                        .frame(width: 32, height: 32)
                    
                    // Show cached thumbnail for images and files, icon for others
                    if let thumbnail = cachedThumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.sm, style: .continuous))
                    } else {
                        itemIcon
                            .foregroundStyle(isSelected ? .white : AdaptiveColors.primaryTextAuto.opacity(0.92))
                            .font(.system(size: 12))
                    }
                }
                .task(id: item.id) {
                    // Load thumbnail asynchronously for images and files
                    guard cachedThumbnail == nil else { return }
                    
                    if item.type == .image {
                        let thumbnail = ThumbnailCache.shared.thumbnail(for: item)
                        await MainActor.run {
                            cachedThumbnail = thumbnail.map {
                                ClipboardImageRounding.rounded($0, cornerRadius: DroppyRadius.sm)
                            }
                        }
                    } else if item.type == .file, let path = item.content {
                        let thumbnail = await ThumbnailCache.shared.loadFileThumbnailAsync(path: path, size: CGSize(width: 64, height: 64))
                        await MainActor.run {
                            cachedThumbnail = thumbnail.map {
                                ClipboardImageRounding.rounded($0, cornerRadius: DroppyRadius.sm)
                            } ?? ThumbnailCache.shared.cachedIcon(forPath: path)
                        }
                    }
                }
                
                // Title and time
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? .white : AdaptiveColors.primaryTextAuto.opacity(0.92))
                        .lineLimit(1)
                    
                    Text(item.date, style: .time)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : AdaptiveColors.secondaryTextAuto.opacity(0.9))
                }
                
                Spacer()
                
                // Right side: status icons (flag + favorite)
                HStack(spacing: 4) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.yellow)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(nsColor: .selectedContentBackgroundColor)
                            : Color.red.opacity(isHovering ? 0.09 : 0.06)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? AdaptiveColors.overlayAuto(0.14)
                            : Color.red.opacity(isHovering ? 0.18 : 0.12),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            Button(action: onPaste) {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            Button {
                manager.toggleFlag(item)
            } label: {
                Label("Remove Flag", systemImage: "flag.slash")
            }
            Button {
                manager.toggleFavorite(item)
            } label: {
                Label(item.isFavorite ? "Unfavorite" : "Favorite", systemImage: item.isFavorite ? "star.slash" : "star")
            }
            if item.type == .image {
                if !ExtensionType.aiBackgroundRemoval.isRemoved && AIInstallManager.shared.isInstalled {
                    Button(action: onRemoveBackground) {
                        Label(
                            isRemovingBackground ? "Removing Background..." : "Remove Background",
                            systemImage: "person.and.background.dotted"
                        )
                    }
                    .disabled(isRemovingBackground)
                } else {
                    Button {
                        // No action - informational only.
                    } label: {
                        Label("Remove Background (Settings > Extensions)", systemImage: "person.and.background.dotted")
                    }
                    .disabled(true)
                }
            }
            Divider()
            Button(role: .destructive) {
                manager.delete(item: item)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    @ViewBuilder
    private var itemIcon: some View {
        switch item.type {
        case .text:
            Image(systemName: "doc.text")
        case .image:
            Image(systemName: "photo")
        case .file:
            Image(systemName: "doc")
        case .url:
            Image(systemName: "link")
        case .color:
            Image(systemName: "paintpalette")
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let isRemovingBackground: Bool
    @Binding var renamingItemId: UUID?
    @Binding var renamingText: String
    let onRename: (String) -> Void
    
    @AppStorage(AppPreferenceKey.clipboardTagsEnabled) private var tagsEnabled = PreferenceDefault.clipboardTagsEnabled
    @ObservedObject private var backgroundRemovalManager = BackgroundRemovalManager.shared
    @State private var isHovering = false
    @State private var dashPhase: CGFloat = 0
    @State private var cachedThumbnail: NSImage? // Async-loaded thumbnail
    @FocusState private var isRenameFocused: Bool

    private var rowBackgroundRemovalProgress: Double? {
        guard isRemovingBackground, backgroundRemovalManager.isProcessing else { return nil }
        return backgroundRemovalManager.progress
    }

    private var rowBackgroundRemovalProgressClamped: Double {
        min(max(rowBackgroundRemovalProgress ?? 0, 0), 1)
    }

    private var rowBackgroundRemovalPercentText: String {
        "\(Int(rowBackgroundRemovalProgressClamped * 100))%"
    }
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon/Thumbnail - smaller and shows real image for images
            ZStack {
                RoundedRectangle(cornerRadius: DroppyRadius.sm, style: .continuous)
                    .fill(AdaptiveColors.overlayAuto(0.1))
                    .frame(width: 32, height: 32)
                
                // Show cached thumbnail for images and files, icon for others
                if let thumbnail = cachedThumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.sm, style: .continuous))
                } else {
                    Image(systemName: iconName(for: item.type))
                        .foregroundStyle(isSelected ? .white : AdaptiveColors.primaryTextAuto)
                        .font(.system(size: 12))
                }
            }
            .task(id: item.id) {
                // Load thumbnail asynchronously for images and files
                guard cachedThumbnail == nil else { return }
                
                if item.type == .image {
                    // Image: load from clipboard image cache
                    let thumbnail = ThumbnailCache.shared.thumbnail(for: item)
                    await MainActor.run {
                        cachedThumbnail = thumbnail.map {
                            ClipboardImageRounding.rounded($0, cornerRadius: DroppyRadius.sm)
                        }
                    }
                } else if item.type == .file, let path = item.content {
                    // File: load QuickLook thumbnail for PDFs, docs, etc.
                    let thumbnail = await ThumbnailCache.shared.loadFileThumbnailAsync(path: path, size: CGSize(width: 64, height: 64))
                    await MainActor.run {
                        cachedThumbnail = thumbnail.map {
                            ClipboardImageRounding.rounded($0, cornerRadius: DroppyRadius.sm)
                        } ?? ThumbnailCache.shared.cachedIcon(forPath: path)
                    }
                }
            }
            
            // Title or rename field
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : AdaptiveColors.primaryTextAuto.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                HStack(spacing: 4) {
                    if let app = item.sourceApp {
                        Text(app)
                            .font(.system(size: 10))
                            .lineLimit(1)
                    }
                    Text(item.date, style: .time)
                        .font(.system(size: 10))
                }
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : AdaptiveColors.secondaryTextAuto.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)  // Fill available space, don't expand parent
            
            Spacer(minLength: 8)
            
            // Status icons (tag dot + key + flag + star)
            HStack(spacing: 4) {
                // Tag dot - shows tag color (only when tags enabled)
                if tagsEnabled, let tag = ClipboardManager.shared.getTag(by: item.tagId) {
                    Circle()
                        .fill(tag.color)
                        .frame(width: 6, height: 6)
                }
                if item.isConcealed {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 9))
                }
                if item.isFlagged {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.red)
                        .font(.system(size: 9))
                }
                if item.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                        .font(.system(size: 9))
                }
            }
        }
        .frame(maxWidth: .infinity)  // Ensure consistent width for all rows
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 42)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? Color(nsColor: .selectedContentBackgroundColor)
                        : AdaptiveColors.overlayAuto(isHovering ? 0.09 : 0.05)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected
                        ? AdaptiveColors.overlayAuto(0.14)
                        : AdaptiveColors.overlayAuto(isHovering ? 0.13 : 0.08),
                    lineWidth: 1
                )
        )
        .overlay {
            if isRemovingBackground {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.76))
                    .overlay(
                        HStack(spacing: 10) {
                            ProgressView(value: rowBackgroundRemovalProgressClamped, total: 1)
                                .progressViewStyle(.linear)
                                .tint(.white.opacity(0.95))
                                .frame(width: 56)

                            Spacer(minLength: 6)

                            Text(rowBackgroundRemovalPercentText)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.98))
                        }
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 3)
                    .allowsHitTesting(false)
                    .transition(.opacity.animation(DroppyAnimation.viewChange))
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
        .droppyPopover(isPresented: renamePopoverPresented, arrowEdge: .top) {
            ClipboardRenamePopover(
                text: $renamingText,
                title: String(localized: "action.edit"),
                placeholder: item.title,
                isFocused: $isRenameFocused,
                onSave: performRename,
                onCancel: {
                    renamePopoverPresented.wrappedValue = false
                }
            )
        }
        .onChange(of: renamingItemId) { _, newValue in
            if newValue == item.id {
                renamingText = item.title
            }
        }
    }
    
    private var renamePopoverPresented: Binding<Bool> {
        Binding(
            get: { renamingItemId == item.id },
            set: { isPresented in
                if !isPresented {
                    renamingItemId = nil
                }
            }
        )
    }
    
    private func performRename() {
        let trimmed = renamingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onRename(trimmed)
        renamingItemId = nil
    }
    
    func iconName(for type: ClipboardType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .color: return "paintpalette"
        }
    }
}

private struct ClipboardRenamePopover: View {
    @Binding var text: String
    let title: String
    let placeholder: String
    @FocusState.Binding var isFocused: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    
    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AdaptiveColors.secondaryTextAuto)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .focused($isFocused)
                .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.95))
                .droppyTextInputChrome(
                    backgroundOpacity: 0.95,
                    borderOpacity: 1.0,
                    useAdaptiveColors: true
                )
                .onSubmit {
                    onSave()
                }
            
            HStack(spacing: 10) {
                Button {
                    onCancel()
                } label: {
                    Text(String(localized: "action.cancel"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DroppyPillButtonStyle(size: .small))
                
                Button {
                    onSave()
                } label: {
                    Text(String(localized: "action.save"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(DroppyAccentButtonStyle(color: .accentColor, size: .small))
                .disabled(trimmedText.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AdaptiveColors.panelBackgroundAuto.opacity(0.97))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AdaptiveColors.subtleBorderAuto.opacity(0.9), lineWidth: 1)
                )
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}

// MARK: - Clipboard Rename TextField


struct ClipboardPreviewView: View {
    let item: ClipboardItem
    var scrollProxy: ScrollViewProxy?
    let showsPrimaryActionsInFooter: Bool
    @Binding var topBarTextEditingItemID: UUID?
    @Binding var topBarTextEditingContent: String
    let onRemoveBackground: () -> Void
    let isRemovingBackground: Bool
    let onPaste: () -> Void
    let onDelete: () -> Void
    
    @ObservedObject private var manager = ClipboardManager.shared
    @AppStorage(AppPreferenceKey.clipboardTagsEnabled) private var tagsEnabled = PreferenceDefault.clipboardTagsEnabled

    @State private var isPasteHovering = false
    @State private var isCopyHovering = false
    @State private var isStarHovering = false
    @State private var isFlagHovering = false
    @State private var isTrashHovering = false
    @State private var starAnimationTrigger = false
    @State private var flagAnimationTrigger = false
    @State private var isTagPopoverVisible = false
    @State private var isDownloadHovering = false
    @State private var isSavingFile = false
    @State private var showSaveSuccess = false
    @State private var showCopySuccess = false
    
    // Animation Namespace
    @Namespace private var animationNamespace
    
    @State private var isExtractingText = false
    
    // Cached Preview Content
    @State private var cachedImage: NSImage?
    @State private var cachedAttributedText: AttributedString?
    @State private var cachedFilePreview: NSImage? // QuickLook preview for file types
    @State private var isLoadingPreview = false
    
    // Link Preview State
    @State private var linkPreviewTitle: String?
    @State private var linkPreviewDescription: String?
    @State private var linkPreviewImage: NSImage?
    @State private var linkPreviewIcon: NSImage?
    @State private var isLoadingLinkPreview = false
    @State private var isDirectImageLink = false
    
    // Multi-Page Document State
    @State private var documentPageCount: Int = 1
    @State private var currentPageIndex: Int = 0
    @State private var isLoadingPage = false
    @State private var swipeOffset: CGFloat = 0
    @State private var showZoomedPreview = false
    
    // Video Preview State
    @State private var videoPlayer: AVPlayer?
    @State private var isVideoFile: Bool = false
    @State private var pageNavigationTask: Task<Void, Never>?
    private let previewLoadDebounceNanos: UInt64 = 60_000_000
    
    // Video file extensions
    private static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
    
    private func isVideoPath(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return Self.videoExtensions.contains(ext)
    }

    private func cancelOutstandingPreviewTasks() {
        pageNavigationTask?.cancel()
        pageNavigationTask = nil
    }
    
    // MARK: - Page Navigation
    
    private enum SwipeDirection {
        case left, right
    }
    
    private func navigateToPage(_ pageIndex: Int, path: String, direction: SwipeDirection) {
        guard pageIndex >= 0 && pageIndex < documentPageCount else { return }
        pageNavigationTask?.cancel()
        
        // Animate out
        let exitOffset: CGFloat = direction == .left ? -300 : 300
        withAnimation(DroppyAnimation.hoverScale) {
            swipeOffset = exitOffset
        }
        
        // Load new page
        isLoadingPage = true
        pageNavigationTask = Task {
            try? await Task.sleep(nanoseconds: previewLoadDebounceNanos)
            guard !Task.isCancelled else { return }
            let newPreview = await ThumbnailCache.shared.loadDocumentPage(path: path, pageIndex: pageIndex, size: CGSize(width: 400, height: 400))
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                currentPageIndex = pageIndex
                
                // Reset offset to opposite side for entrance
                swipeOffset = direction == .left ? 300 : -300
                
                // Update preview
                cachedFilePreview = newPreview.map {
                    ClipboardImageRounding.rounded($0, cornerRadius: DroppyRadius.large)
                }
                isLoadingPage = false
                
                // Animate in
                withAnimation(DroppyAnimation.state) {
                    swipeOffset = 0
                }
            }
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        if let str = item.content {
            NSPasteboard.general.setString(str, forType: .string)
        } else if let imgData = item.loadImageData() {
            NSPasteboard.general.setData(imgData, forType: .tiff)
        }
        
        withAnimation(DroppyAnimation.stateEmphasis) {
            showCopySuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopySuccess = false
            }
        }
    }
    
    private func saveToFile() {
        isSavingFile = true
        
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let fileName: String
        let fileExtension: String
        
        switch item.type {
        case .image:
            fileName = item.customTitle ?? "Image_\(Int(Date().timeIntervalSince1970))"
            fileExtension = "png"
        case .text, .url:
            fileName = item.customTitle ?? "Text_\(Int(Date().timeIntervalSince1970))"
            fileExtension = "txt"
        case .file:
            if let path = item.content {
                let url = URL(fileURLWithPath: path)
                fileName = url.deletingPathExtension().lastPathComponent
                fileExtension = url.pathExtension
            } else {
                fileName = "File_\(Int(Date().timeIntervalSince1970))"
                fileExtension = ""
            }
        case .color:
            fileName = "Color_\(Int(Date().timeIntervalSince1970))"
            fileExtension = "txt"
        }
        
        var destinationURL = downloads.appendingPathComponent(fileName).appendingPathExtension(fileExtension)
        
        // Handle collisions
        var counter = 1
        while FileManager.default.fileExists(atPath: destinationURL.path) {
            destinationURL = downloads.appendingPathComponent("\(fileName)_\(counter)").appendingPathExtension(fileExtension)
            counter += 1
        }
        
        do {
            switch item.type {
            case .image:
                if let data = item.loadImageData(),
                   let nsImage = NSImage(data: data),
                   let tiffData = nsImage.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffData),
                   let pngData = bitmap.representation(using: .png, properties: [:]) {
                    try pngData.write(to: destinationURL)
                }
            case .text, .url, .color:
                if let content = item.content {
                    try content.write(to: destinationURL, atomically: true, encoding: .utf8)
                }
            case .file:
                if let path = item.content {
                    let sourceURL = URL(fileURLWithPath: path)
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                }
            }
            
            // Success Feedback
            withAnimation(DroppyAnimation.stateEmphasis) {
                showSaveSuccess = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    showSaveSuccess = false
                }
            }
        } catch {
            print("Direct save error: \(error.localizedDescription)")
        }
        
        isSavingFile = false
    }

    private var isTextEditingFromHeader: Bool {
        item.type == .text && topBarTextEditingItemID == item.id
    }

    private func releasePreviewResources(clearCachedContent: Bool) {
        videoPlayer?.pause()
        videoPlayer?.replaceCurrentItem(with: nil)
        videoPlayer = nil
        isVideoFile = false

        guard clearCachedContent else { return }
        cachedImage = nil
        cachedAttributedText = nil
        cachedFilePreview = nil
        linkPreviewTitle = nil
        linkPreviewDescription = nil
        linkPreviewImage = nil
        linkPreviewIcon = nil
        isLoadingLinkPreview = false
        isDirectImageLink = false
        showZoomedPreview = false
        isLoadingPage = false
    }

    private func decodeImageForPreview(_ data: Data) async -> NSImage? {
        let decodeTask = Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard !Task.isCancelled else { return nil }
            return NSImage(data: data)
        }

        return await withTaskCancellationHandler {
            await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }
    }

    private func decodeRTFForPreview(_ rtfData: Data) async -> AttributedString? {
        let decodeTask = Task.detached(priority: .userInitiated) { () -> AttributedString? in
            guard !Task.isCancelled else { return nil }
            return try? rtfToAttributedString(rtfData)
        }

        return await withTaskCancellationHandler {
            await decodeTask.value
        } onCancel: {
            decodeTask.cancel()
        }
    }

    @ViewBuilder
    private var imagePreviewContent: some View {
        if let nsImg = cachedImage {
            ZStack(alignment: .bottomTrailing) {
                RoundedPreviewImageSurface(
                    image: nsImg,
                    cornerRadius: DroppyRadius.large,
                    contentPadding: DroppySpacing.md
                )

                // OCR Button
                Button {
                    guard !isExtractingText else { return }
                    isExtractingText = true
                    Task {
                        do {
                            let text = try await OCRService.shared.performOCR(on: nsImg)
                            await MainActor.run {
                                isExtractingText = false
                                OCRWindowController.shared.presentExtractedText(text)
                            }
                        } catch {
                            await MainActor.run {
                                isExtractingText = false
                                print("OCR Error: \(error)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isExtractingText {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "text.viewfinder")
                        }
                        Text(isExtractingText ? "Extracting…" : "Extract Text")
                    }
                }
                .buttonStyle(DroppyPillButtonStyle(size: .small))
                .padding(DroppySpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
        } else if isLoadingPreview {
            ProgressView()
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Content Preview
            VStack {
                switch item.type {
                case .text:
                    if isTextEditingFromHeader {
                        TextEditor(text: $topBarTextEditingContent)
                            .font(.system(.body, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .foregroundStyle(AdaptiveColors.primaryTextAuto)
                            .droppyTextInputChrome(
                                cornerRadius: DroppyRadius.ml,
                                horizontalPadding: 10,
                                verticalPadding: 10
                            )

                    } else {
                        ScrollView {
                            if let attributed = cachedAttributedText {
                                Text(attributed)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            } else if isLoadingPreview {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding()
                            } else {
                                // Truncate very long content for performance
                                let content = item.content ?? ""
                                let maxPreviewLength = 50000
                                let truncatedContent = content.count > maxPreviewLength 
                                    ? String(content.prefix(maxPreviewLength)) + "\n\n[Content truncated - \(content.count) characters total]"
                                    : content
                                
                                Text(truncatedContent)
                                    .font(.body)
                                    .foregroundStyle(AdaptiveColors.primaryTextAuto)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    
                case .url:
                    URLPreviewCard(
                        item: item,
                        isLoading: isLoadingLinkPreview,
                        isDirectImage: isDirectImageLink,
                        title: linkPreviewTitle,
                        description: linkPreviewDescription,
                        image: linkPreviewImage,
                        icon: linkPreviewIcon
                    )
                    .padding(.vertical)
                    
                case .image:
                    imagePreviewContent
                    
                case .file:
                    if let path = item.content {
                        VStack(spacing: 12) {
                            // Check if this is a video file
                            if isVideoFile, let player = videoPlayer {
                                // Video Player View
                                SafeVideoPreview(player: player)
                                    .aspectRatio(16/9, contentMode: .fit)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(DroppySpacing.md)
                                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
                                    .droppyCardShadow(opacity: 0.3)
                                    .onAppear {
                                        player.play()
                                    }
                                    .onDisappear {
                                        player.pause()
                                    }
                            } else {
                                // Document preview with swipe gesture for multi-page
                                ZStack {
                                    if let preview = cachedFilePreview {
                                        RoundedPreviewImageSurface(
                                            image: preview,
                                            cornerRadius: DroppyRadius.large,
                                            contentPadding: DroppySpacing.md
                                        )
                                            .droppyCardShadow(opacity: 0.3)
                                            .offset(x: swipeOffset)
                                            .animation(DroppyAnimation.state, value: swipeOffset)
                                    } else if isLoadingPreview || isLoadingPage {
                                        ProgressView()
                                            .controlSize(.large)
                                            .padding(DroppySpacing.xxxl + DroppySpacing.sm) // 40pt for large empty state
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    } else {
                                        Image(nsImage: ThumbnailCache.shared.cachedIcon(forPath: path))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 120, height: 120)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
                                .gesture(
                                    DragGesture(minimumDistance: 30)
                                        .onChanged { value in
                                            // Only allow horizontal swipe if multi-page
                                            guard documentPageCount > 1 else { return }
                                            swipeOffset = value.translation.width * 0.4
                                        }
                                        .onEnded { value in
                                            guard documentPageCount > 1 else { return }
                                            let threshold: CGFloat = 50
                                            
                                            if value.translation.width < -threshold && currentPageIndex < documentPageCount - 1 {
                                                // Swipe left - next page
                                                navigateToPage(currentPageIndex + 1, path: path, direction: .left)
                                            } else if value.translation.width > threshold && currentPageIndex > 0 {
                                                // Swipe right - previous page
                                                navigateToPage(currentPageIndex - 1, path: path, direction: .right)
                                            } else {
                                                // Snap back
                                                withAnimation(DroppyAnimation.state) {
                                                    swipeOffset = 0
                                                }
                                            }
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    // Double-click to zoom
                                    showZoomedPreview = true
                                }
                                
                                // Page Navigation (only show for multi-page docs)
                                if documentPageCount > 1 {
                                    HStack(spacing: 8) {
                                        // Previous button
                                        Button {
                                            if currentPageIndex > 0 {
                                                navigateToPage(currentPageIndex - 1, path: path, direction: .right)
                                            }
                                        } label: {
                                            Image(systemName: "chevron.backward")
                                        }
                                        .buttonStyle(DroppyCircleButtonStyle(size: 28))
                                        .disabled(currentPageIndex == 0)
                                        .opacity(currentPageIndex > 0 ? 1.0 : 0.4)
                                        
                                        // Page indicators (dots)
                                        if documentPageCount <= 10 {
                                            HStack(spacing: 6) {
                                                ForEach(0..<documentPageCount, id: \.self) { index in
                                                    Circle()
                                                        .fill(index == currentPageIndex ? AdaptiveColors.primaryTextAuto : AdaptiveColors.overlayAuto(0.3))
                                                        .frame(width: 6, height: 6)
                                                        .scaleEffect(index == currentPageIndex ? 1.2 : 1.0)
                                                        .animation(DroppyAnimation.hover, value: currentPageIndex)
                                                        .onTapGesture {
                                                            if index != currentPageIndex {
                                                                let direction: SwipeDirection = index > currentPageIndex ? .left : .right
                                                                navigateToPage(index, path: path, direction: direction)
                                                            }
                                                        }
                                                }
                                            }
                                        } else {
                                            // For many pages, show text
                                            Text("\(currentPageIndex + 1) / \(documentPageCount)")
                                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                                .foregroundStyle(.secondary)
                                                .monospacedDigit()
                                        }
                                        
                                        // Next button
                                        Button {
                                            if currentPageIndex < documentPageCount - 1 {
                                                navigateToPage(currentPageIndex + 1, path: path, direction: .left)
                                            }
                                        } label: {
                                            Image(systemName: "chevron.forward")
                                        }
                                        .buttonStyle(DroppyCircleButtonStyle(size: 28))
                                        .disabled(currentPageIndex == documentPageCount - 1)
                                        .opacity(currentPageIndex < documentPageCount - 1 ? 1.0 : 0.4)
                                        
                                        // Zoom button for expanded preview
                                        Button {
                                            showZoomedPreview = true
                                        } label: {
                                            Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                                        }
                                        .buttonStyle(DroppyCircleButtonStyle(size: 28))
                                        .help("Expand Preview")
                                    }
                                    .padding(.top, 4)
                                }
                                
                                // Zoom button for single-page docs (when page nav isn't shown)
                                if documentPageCount == 1 {
                                    Button {
                                        showZoomedPreview = true
                                    } label: {
                                        Image(systemName: "arrow.up.backward.and.arrow.down.forward")
                                    }
                                    .buttonStyle(DroppyCircleButtonStyle(size: 28))
                                    .help("Expand Preview")
                                    .padding(.top, 4)
                                }
                            }
                            
                            // File name (shared between video and document)
                            VStack(spacing: 4) {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                    .font(.headline)
                                    .foregroundStyle(AdaptiveColors.primaryTextAuto)
                                    .multilineTextAlignment(.center)
                                Text(path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .padding(.bottom, DroppySpacing.md)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                        .task(id: item.id) {
                            cancelOutstandingPreviewTasks()
                            try? await Task.sleep(nanoseconds: previewLoadDebounceNanos)
                            guard !Task.isCancelled else { return }

                            // Check if this is a video file
                            if isVideoPath(path) {
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    isVideoFile = true
                                    let url = URL(fileURLWithPath: path)
                                    videoPlayer = AVPlayer(url: url)
                                }
                                return
                            }
                            
                            // Not a video - load document info and first page
                            await MainActor.run {
                                isVideoFile = false
                                videoPlayer = nil
                            }
                            
                            currentPageIndex = 0
                            documentPageCount = ThumbnailCache.shared.pageCount(for: path)
                            
                            isLoadingPreview = true
                            let preview = await ThumbnailCache.shared.loadDocumentPage(path: path, pageIndex: 0, size: CGSize(width: 400, height: 400))
                            guard !Task.isCancelled else { return }
                            await MainActor.run {
                                cachedFilePreview = preview.map {
                                    ClipboardImageRounding.rounded($0, cornerRadius: DroppyRadius.large)
                                }
                                isLoadingPreview = false
                            }
                        }
                        .sheet(isPresented: $showZoomedPreview) {
                            ZoomedDocumentPreviewSheet(
                                item: item,
                                initialPageIndex: currentPageIndex,
                                pageCount: documentPageCount
                            )
                            .presentationBackground(.clear)
                            .onAppear {
                                ClipboardWindowController.shared.styleAttachedSheetForLiquidGlass()
                            }
                        }
                    }
                default:
                     Text("Preview not available")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                    .fill(isTextEditingFromHeader ? AdaptiveColors.buttonBackgroundAuto.opacity(0.95) : AdaptiveColors.overlayAuto(0.05))
            )
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                    .strokeBorder(isTextEditingFromHeader ? AdaptiveColors.subtleBorderAuto : .clear, lineWidth: 1)
            )
            .animation(DroppyAnimation.viewChange, value: isTextEditingFromHeader)
            .onAppear {
                manager.isEditingContent = isTextEditingFromHeader
            }
            .onChange(of: isTextEditingFromHeader) { _, editing in
                // Sync with shared state so Cmd+V shortcut is disabled during editing
                manager.isEditingContent = editing
            }
            
            // Metadata Footer
            HStack {
                if let app = item.sourceApp {
                    Label(app, systemImage: "app")
                }
                Spacer()
                Text(item.date, style: .date)
                Text(item.date, style: .time)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            
            if showsPrimaryActionsInFooter {
                HStack(spacing: 12) {
                    Button(action: onPaste) {
                        Text("Paste")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DroppyAccentButtonStyle(color: AdaptiveColors.selectionBlueAuto, size: .medium))
                    .matchedGeometryEffect(id: "PrimaryAction", in: animationNamespace)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    Button(action: copyToClipboard) {
                        ZStack {
                            if showCopySuccess {
                                Image(systemName: "checkmark")
                                    .fontWeight(.bold)
                            } else {
                                Text("Copy")
                            }
                        }
                        .frame(width: 70)
                    }
                    .buttonStyle(DroppyAccentButtonStyle(color: showCopySuccess ? .green : AdaptiveColors.selectionBlueAuto, size: .medium))
                    .matchedGeometryEffect(id: "SecondaryAction", in: animationNamespace)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    Button(action: saveToFile) {
                        ZStack {
                            if showSaveSuccess {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            } else if isSavingFile {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(AdaptiveColors.primaryTextAuto)
                            } else {
                                Image(systemName: "square.and.arrow.down")
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 40))
                    .help("Save to Downloads")
                    .disabled(isSavingFile || showSaveSuccess)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    if item.type == .image {
                        if !ExtensionType.aiBackgroundRemoval.isRemoved, AIInstallManager.shared.isInstalled {
                            Button(action: onRemoveBackground) {
                                ZStack {
                                    if isRemovingBackground {
                                        ProgressView()
                                            .controlSize(.small)
                                            .tint(AdaptiveColors.primaryTextAuto)
                                    } else {
                                        Image(systemName: "person.and.background.dotted")
                                    }
                                }
                            }
                            .buttonStyle(DroppyCircleButtonStyle(size: 40))
                            .help(isRemovingBackground ? "Removing Background..." : "Remove Background")
                            .disabled(isRemovingBackground)
                        } else {
                            Button {
                                // No action - informational only.
                            } label: {
                                Image(systemName: "person.and.background.dotted")
                            }
                            .buttonStyle(DroppyCircleButtonStyle(size: 40))
                            .help("Remove Background (Settings > Extensions)")
                            .disabled(true)
                        }
                    }

                    Button {
                        withAnimation(DroppyAnimation.scalePop) {
                            starAnimationTrigger.toggle()
                        }
                        let willBeFavorite = !item.isFavorite
                        manager.toggleFavorite(item)
                        if willBeFavorite {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(DroppyAnimation.transition) {
                                    scrollProxy?.scrollTo(item.id, anchor: .top)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(item.isFavorite ? .yellow : AdaptiveColors.primaryTextAuto.opacity(0.85))
                            .symbolEffect(.bounce, value: starAnimationTrigger)
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 40))
                    .help("Toggle Favorite")

                    Button {
                        withAnimation(DroppyAnimation.scalePop) {
                            flagAnimationTrigger.toggle()
                        }
                        let willBeFlagged = !item.isFlagged
                        manager.toggleFlag(item)
                        if willBeFlagged {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                withAnimation(DroppyAnimation.transition) {
                                    scrollProxy?.scrollTo(item.id, anchor: .top)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: item.isFlagged ? "flag.fill" : "flag")
                            .foregroundStyle(item.isFlagged ? .red : AdaptiveColors.primaryTextAuto.opacity(0.85))
                            .symbolEffect(.bounce, value: flagAnimationTrigger)
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 40))
                    .help("Flag as Important")

                    if tagsEnabled {
                        Button {
                            isTagPopoverVisible.toggle()
                        } label: {
                            ZStack {
                                Image(systemName: "tag")
                                    .foregroundStyle(item.tagId != nil ? (manager.getTag(by: item.tagId)?.color ?? .cyan) : AdaptiveColors.primaryTextAuto.opacity(0.85))
                            }
                        }
                        .buttonStyle(DroppyCircleButtonStyle(size: 40))
                        .help("Assign Tag")
                        .droppyPopover(isPresented: $isTagPopoverVisible, arrowEdge: .bottom) {
                            VStack(spacing: 4) {
                                ForEach(manager.tags) { tag in
                                    Button {
                                        if item.tagId == tag.id {
                                            manager.removeTagFromItem(item)
                                        } else {
                                            manager.assignTag(tag, to: item)
                                        }
                                        isTagPopoverVisible = false
                                    } label: {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(tag.color)
                                                .frame(width: 10, height: 10)
                                            Text(tag.name)
                                                .font(.system(size: 12))
                                            Spacer()
                                            if item.tagId == tag.id {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.cyan)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(item.tagId == tag.id ? AdaptiveColors.overlayAuto(0.1) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.sm, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }

                                if item.tagId != nil {
                                    Divider()
                                    Button {
                                        manager.removeTagFromItem(item)
                                        isTagPopoverVisible = false
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "tag.slash")
                                                .font(.system(size: 10))
                                            Text("Remove Tag")
                                                .font(.system(size: 12))
                                        }
                                        .foregroundStyle(.red)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                }

                                if manager.tags.isEmpty {
                                    Text("No tags yet")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                        .padding(DroppySpacing.sm)
                                }
                            }
                            .padding(DroppySpacing.sm)
                            .frame(minWidth: 140)
                            .background { Rectangle().fill(.ultraThinMaterial) }
                        }
                    }

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 40))
                    .help("Delete (Backspace)")
                }
                .buttonStyle(DroppyCardButtonStyle())
            }
        }
        .padding(DroppySpacing.xl)
        .onDisappear {
            cancelOutstandingPreviewTasks()
            releasePreviewResources(clearCachedContent: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clipboardWindowDidHide)) { _ in
            cancelOutstandingPreviewTasks()
            releasePreviewResources(clearCachedContent: true)
        }
        .task(id: item.id) {
            // Asynchronously load and process preview content
            cancelOutstandingPreviewTasks()
            try? await Task.sleep(nanoseconds: previewLoadDebounceNanos)
            guard !Task.isCancelled else { return }
            isLoadingPreview = true

            // Ensure media decoders and previous preview state are released before loading a new item.
            releasePreviewResources(clearCachedContent: true)
            
            // Reset page navigation state
            currentPageIndex = 0
            documentPageCount = 1
            swipeOffset = 0
            
            switch item.type {
            case .image:
                if let data = item.loadImageData() {
                    let decodedImage = await decodeImageForPreview(data)
                    guard !Task.isCancelled else { return }
                    cachedImage = decodedImage.map {
                        ClipboardImageRounding.rounded($0, cornerRadius: DroppyRadius.large)
                    }
                }
                
            case .text:
                if let rtfData = item.rtfData {
                    let attributed = await decodeRTFForPreview(rtfData)
                    guard !Task.isCancelled else { return }
                    cachedAttributedText = attributed
                }
                
            case .url:
                // Fetch link preview
                if let urlString = item.content {
                    isLoadingLinkPreview = true
                    
                    // Clear previous states
                    linkPreviewTitle = nil
                    linkPreviewDescription = nil
                    linkPreviewImage = nil
                    linkPreviewIcon = nil
                    isDirectImageLink = false
                    
                    // Check if it's a direct image link
                    if LinkPreviewService.shared.isDirectImageURL(urlString) {
                        isDirectImageLink = true
                        let fetchedImage = await LinkPreviewService.shared.fetchImagePreview(for: urlString)
                        guard !Task.isCancelled else { return }
                        linkPreviewImage = fetchedImage.map {
                            ClipboardImageRounding.rounded($0, cornerRadius: DroppyRadius.large)
                        }
                    } else {
                        // Fetch website metadata
                        if let metadata = await LinkPreviewService.shared.fetchMetadata(for: urlString) {
                            guard !Task.isCancelled else { return }
                            linkPreviewTitle = metadata.title
                            linkPreviewDescription = metadata.description
                            
                            if let imageData = metadata.image {
                                if let image = NSImage(data: imageData) {
                                    linkPreviewImage = ClipboardImageRounding.rounded(image, cornerRadius: DroppyRadius.large)
                                }
                            }
                            
                            if let iconData = metadata.icon {
                                linkPreviewIcon = NSImage(data: iconData)
                            }
                            
                            // If still no image but it's an image link we missed
                            if linkPreviewImage == nil && LinkPreviewService.shared.isDirectImageURL(urlString) {
                                linkPreviewImage = await LinkPreviewService.shared.fetchImagePreview(for: urlString)
                            }
                        }
                    }
                    
                    isLoadingLinkPreview = false
                }
                
            default: break
            }
            
            isLoadingPreview = false
        }
    }
}

// MARK: - RTF Helper
nonisolated private func rtfToAttributedString(_ data: Data) throws -> AttributedString {
    let nsAttr = try NSAttributedString(
        data: data,
        options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil
    )
    
    // PERFORMANCE: Limit to 50K characters to prevent CPU spike with huge text
    let maxPreviewLength = 50000
    let isTruncated = nsAttr.length > maxPreviewLength
    
    // Create a mutable copy, truncated if necessary
    let mutable: NSMutableAttributedString
    if isTruncated {
        let truncatedRange = NSRange(location: 0, length: maxPreviewLength)
        mutable = NSMutableAttributedString(attributedString: nsAttr.attributedSubstring(from: truncatedRange))
        // Add truncation notice
        let truncationNotice = NSAttributedString(
            string: "\n\n[Content truncated - \(nsAttr.length) characters total]",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: NSFont.systemFont(ofSize: 12)]
        )
        mutable.append(truncationNotice)
    } else {
        mutable = NSMutableAttributedString(attributedString: nsAttr)
    }
    
    // Scale font size up if it's too small (often RTF is 11pt/12pt)
    mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
        if let font = value as? NSFont {
            if font.pointSize < 14 {
                 // Creating a new font with the same descriptor but larger size
                 if let newFont = NSFont(descriptor: font.fontDescriptor, size: 14) {
                     mutable.addAttribute(.font, value: newFont, range: range)
                 }
            }
        }
    }
    
    // Normalize text color for readability across light and dark appearances.
    mutable.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
        mutable.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
    }
    
    // Remove background color to ensure transparency (avoid White on White)
    mutable.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
        if value != nil {
            mutable.removeAttribute(.backgroundColor, range: range)
        }
    }
    
    return AttributedString(mutable)
}

private enum ClipboardImageRounding {
    static func rounded(_ image: NSImage, cornerRadius: CGFloat) -> NSImage {
        let sourceSize = image.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return image }
        let minSide = min(sourceSize.width, sourceSize.height)
        let adaptiveRadius = min(max(cornerRadius, minSide * 0.025), minSide * 0.5)

        let rounded = NSImage(size: sourceSize)
        rounded.lockFocus()
        defer { rounded.unlockFocus() }

        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: sourceSize)).fill()

        let path = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: sourceSize),
            xRadius: adaptiveRadius,
            yRadius: adaptiveRadius
        )
        path.addClip()

        image.draw(
            in: NSRect(origin: .zero, size: sourceSize),
            from: NSRect(origin: .zero, size: sourceSize),
            operation: .sourceOver,
            fraction: 1.0
        )

        return rounded
    }
}

private struct RoundedPreviewImageSurface: View {
    let image: NSImage
    let cornerRadius: CGFloat
    let contentPadding: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let maxWidth = max(0, geometry.size.width - (contentPadding * 2))
            let maxHeight = max(0, geometry.size.height - (contentPadding * 2))

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Zoomed Document Preview Sheet

/// Full-screen sheet for viewing documents with larger preview, page navigation, OCR and all actions
struct ZoomedDocumentPreviewSheet: View {
    let item: ClipboardItem
    let initialPageIndex: Int
    let pageCount: Int
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentPage: Int = 0
    @State private var pagePreview: NSImage?
    @State private var isLoading = true
    @State private var swipeOffset: CGFloat = 0
    @State private var isPerformingOCR = false
    @State private var showCopySuccess = false
    @State private var showOCRSuccess = false
    @State private var ocrCopiedText: String = ""
    
    // Zoom state
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 5.0
    
    private var filePath: String? { item.content }
    private var fileName: String {
        guard let path = filePath else { return "Document" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with title and close button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(.headline)
                        .foregroundStyle(AdaptiveColors.primaryTextAuto)
                        .lineLimit(1)
                    
                    if pageCount > 1 {
                        Text("Page \(currentPage + 1) of \(pageCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 28))
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Large preview area with zoom and swipe
            GeometryReader { geometry in
                ZStack {
                    if let preview = pagePreview {
                        Image(nsImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .scaleEffect(zoomScale, anchor: .center)
                            .offset(x: swipeOffset + offset.width, y: offset.height)
                            .animation(DroppyAnimation.state, value: swipeOffset)
                            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
                            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                            .gesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        let newScale = lastZoomScale * value
                                        zoomScale = min(max(newScale, minZoom), maxZoom)
                                    }
                                    .onEnded { _ in
                                        withAnimation(DroppyAnimation.state) {
                                            // Snap to 1x if close
                                            if zoomScale < 1.1 {
                                                zoomScale = 1.0
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                            lastZoomScale = zoomScale
                                        }
                                    }
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if zoomScale > 1.0 {
                                            // Pan when zoomed
                                            offset = CGSize(
                                                width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height
                                            )
                                        } else if pageCount > 1 {
                                            // Page swipe when not zoomed
                                            swipeOffset = value.translation.width * 0.5
                                        }
                                    }
                                    .onEnded { value in
                                        if zoomScale > 1.0 {
                                            // Clamp pan offset within bounds
                                            let maxOffsetX = geometry.size.width * (zoomScale - 1) / 2
                                            let maxOffsetY = geometry.size.height * (zoomScale - 1) / 2
                                            
                                            withAnimation(DroppyAnimation.state) {
                                                offset = CGSize(
                                                    width: min(max(offset.width, -maxOffsetX), maxOffsetX),
                                                    height: min(max(offset.height, -maxOffsetY), maxOffsetY)
                                                )
                                            }
                                            lastOffset = offset
                                        } else if pageCount > 1 {
                                            let threshold: CGFloat = 80
                                            
                                            if value.translation.width < -threshold && currentPage < pageCount - 1 {
                                                navigateToPage(currentPage + 1, direction: .left)
                                            } else if value.translation.width > threshold && currentPage > 0 {
                                                navigateToPage(currentPage - 1, direction: .right)
                                            } else {
                                                withAnimation(DroppyAnimation.state) {
                                                    swipeOffset = 0
                                                }
                                            }
                                        }
                                    }
                            )
                            .gesture(
                                TapGesture(count: 2)
                                    .onEnded {
                                        withAnimation(DroppyAnimation.state) {
                                            if zoomScale > 1.0 {
                                                // Reset to 1x
                                                zoomScale = 1.0
                                                lastZoomScale = 1.0
                                                offset = .zero
                                                lastOffset = .zero
                                            } else {
                                                // Zoom to 2x
                                                zoomScale = 2.0
                                                lastZoomScale = 2.0
                                            }
                                        }
                                    }
                            )
                        
                        // Zoom controls overlay
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                HStack(spacing: 8) {
                                    // Zoom out
                                    Button {
                                        withAnimation(DroppyAnimation.state) {
                                            zoomScale = max(zoomScale - 0.5, minZoom)
                                            lastZoomScale = zoomScale
                                            if zoomScale <= 1.0 {
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "minus.magnifyingglass")
                                    }
                                    .buttonStyle(DroppyCircleButtonStyle(size: 32))
                                    .disabled(zoomScale <= minZoom)
                                    .opacity(zoomScale <= minZoom ? 0.4 : 1.0)
                                    
                                    // Zoom level indicator
                                    Text("\(Int(zoomScale * 100))%")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                                        .monospacedDigit()
                                        .frame(width: 44)
                                    
                                    // Zoom in
                                    Button {
                                        withAnimation(DroppyAnimation.state) {
                                            zoomScale = min(zoomScale + 0.5, maxZoom)
                                            lastZoomScale = zoomScale
                                        }
                                    } label: {
                                        Image(systemName: "plus.magnifyingglass")
                                    }
                                    .buttonStyle(DroppyCircleButtonStyle(size: 32))
                                    .disabled(zoomScale >= maxZoom)
                                    .opacity(zoomScale >= maxZoom ? 0.4 : 1.0)
                                    
                                    // Reset zoom (only show when zoomed)
                                    if zoomScale > 1.0 {
                                        Button {
                                            withAnimation(DroppyAnimation.state) {
                                                zoomScale = 1.0
                                                lastZoomScale = 1.0
                                                offset = .zero
                                                lastOffset = .zero
                                            }
                                        } label: {
                                            Image(systemName: "arrow.counterclockwise")
                                        }
                                        .buttonStyle(DroppyCircleButtonStyle(size: 32))
                                        .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(DroppySpacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: DroppyRadius.xl, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                )
                            }
                            .padding(DroppySpacing.md)
                        }
                    } else if isLoading {
                        ProgressView()
                            .controlSize(.large)
                    } else if let path = filePath {
                        Image(nsImage: ThumbnailCache.shared.cachedIcon(forPath: path))
                            .resizable()
                            .frame(width: 120, height: 120)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
            
            // Page navigation
            if pageCount > 1 {
                HStack(spacing: 12) {
                    Button {
                        if currentPage > 0 {
                            navigateToPage(currentPage - 1, direction: .right)
                        }
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 36))
                    .disabled(currentPage == 0)
                    .opacity(currentPage > 0 ? 1.0 : 0.4)
                    
                    // Page dots or text
                    if pageCount <= 12 {
                        HStack(spacing: 8) {
                            ForEach(0..<pageCount, id: \.self) { index in
                                Circle()
                                    .fill(index == currentPage ? AdaptiveColors.primaryTextAuto : AdaptiveColors.overlayAuto(0.3))
                                    .frame(width: 8, height: 8)
                                    .scaleEffect(index == currentPage ? 1.3 : 1.0)
                                    .animation(DroppyAnimation.hover, value: currentPage)
                                    .onTapGesture {
                                        if index != currentPage {
                                            navigateToPage(index, direction: index > currentPage ? .left : .right)
                                        }
                                    }
                            }
                        }
                    } else {
                        Text("\(currentPage + 1) / \(pageCount)")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                            .monospacedDigit()
                    }
                    
                    Button {
                        if currentPage < pageCount - 1 {
                            navigateToPage(currentPage + 1, direction: .left)
                        }
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 36))
                    .disabled(currentPage == pageCount - 1)
                    .opacity(currentPage < pageCount - 1 ? 1.0 : 0.4)
                }
                .padding(.vertical, 16)
            }
            
            // Action buttons with Droppy pill style
            HStack(spacing: 12) {
                // OCR Button
                Group {
                    if showOCRSuccess {
                        Button {
                            performOCR()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                Text("Text Copied!")
                            }
                        }
                        .buttonStyle(DroppyAccentButtonStyle(color: .green, size: .medium))
                    } else {
                        Button {
                            performOCR()
                        } label: {
                            HStack(spacing: 6) {
                                if isPerformingOCR {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "text.viewfinder")
                                }
                                Text("OCR")
                            }
                        }
                        .buttonStyle(DroppyPillButtonStyle(size: .medium))
                        .disabled(isPerformingOCR)
                    }
                }
                
                // Copy Button
                Button {
                    copyFile()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showCopySuccess ? "checkmark" : "doc.on.doc")
                        Text(showCopySuccess ? "Copied!" : "Copy")
                    }
                }
                .buttonStyle(showCopySuccess ? DroppyAccentButtonStyle(color: .green, size: .medium) : DroppyAccentButtonStyle(color: AdaptiveColors.selectionBlueAuto, size: .medium))
                
                // Open in Finder
                Button {
                    openInFinder()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder")
                        Text("Finder")
                    }
                }
                .buttonStyle(DroppyPillButtonStyle(size: .medium))
                
                // QuickLook
                Button {
                    openWithQuickLook()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye")
                        Text("QuickLook")
                    }
                }
                .buttonStyle(DroppyPillButtonStyle(size: .medium))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 700, minHeight: 600)
        .background(AdaptiveColors.panelBackgroundAuto)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            if currentPage > 0 && pageCount > 1 {
                navigateToPage(currentPage - 1, direction: .right)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if currentPage < pageCount - 1 && pageCount > 1 {
                navigateToPage(currentPage + 1, direction: .left)
                return .handled
            }
            return .ignored
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            currentPage = initialPageIndex
            loadPage(initialPageIndex)
        }
    }
    
    private enum SwipeDirection {
        case left, right
    }
    
    private func navigateToPage(_ pageIndex: Int, direction: SwipeDirection) {
        guard pageIndex >= 0 && pageIndex < pageCount else { return }
        
        // Animate out
        let exitOffset: CGFloat = direction == .left ? -400 : 400
        withAnimation(DroppyAnimation.hoverScale) {
            swipeOffset = exitOffset
        }
        
        // Load new page
        isLoading = true
        Task {
            guard let path = filePath else { return }
            let newPreview = await ThumbnailCache.shared.loadDocumentPage(path: path, pageIndex: pageIndex, size: CGSize(width: 800, height: 800))
            
            await MainActor.run {
                currentPage = pageIndex
                
                // Reset zoom and pan when changing pages
                zoomScale = 1.0
                lastZoomScale = 1.0
                offset = .zero
                lastOffset = .zero
                
                // Reset offset to opposite side
                swipeOffset = direction == .left ? 400 : -400
                
                pagePreview = newPreview
                isLoading = false
                
                // Animate in
                withAnimation(DroppyAnimation.state) {
                    swipeOffset = 0
                }
            }
        }
    }
    
    private func loadPage(_ pageIndex: Int) {
        guard let path = filePath else { return }
        isLoading = true
        
        Task {
            let preview = await ThumbnailCache.shared.loadDocumentPage(path: path, pageIndex: pageIndex, size: CGSize(width: 800, height: 800))
            await MainActor.run {
                pagePreview = preview
                isLoading = false
            }
        }
    }
    
    private func performOCR() {
        guard let preview = pagePreview else { return }
        isPerformingOCR = true
        
        Task {
            do {
                let ocrResult = try await OCRService.shared.performOCR(on: preview)
                await MainActor.run {
                    isPerformingOCR = false
                    if !ocrResult.isEmpty {
                        TextCopyFeedback.copyOCRText(ocrResult)
                        ocrCopiedText = ocrResult
                        showOCRSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            showOCRSuccess = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isPerformingOCR = false
                }
            }
        }
    }
    
    private func copyFile() {
        guard let path = filePath else { return }
        let url = URL(fileURLWithPath: path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
        
        withAnimation {
            showCopySuccess = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopySuccess = false
            }
        }
    }
    
    private func openInFinder() {
        guard let path = filePath else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    private func openWithQuickLook() {
        guard let path = filePath else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Multi-Select Preview View

struct MultiSelectPreviewView: View {
    let items: [ClipboardItem]
    let onPasteAll: () -> Void
    let onCopyAll: () -> Void
    let onSaveAll: () -> Void
    let onDeleteAll: () -> Void
    
    @State private var isPasteHovering = false
    @State private var isCopyHovering = false
    @State private var isSaveHovering = false
    @State private var isDeleteHovering = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Stacked cards preview
            ZStack {
                ForEach(Array(items.prefix(5).enumerated().reversed()), id: \.element.id) { index, item in
                    StackedCardView(item: item, index: index, totalCount: min(items.count, 5))
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                }
            }
            .frame(height: 180)
            .animation(DroppyAnimation.transition, value: items.count)
            
            // Selection count badge - styled like DroppyPillButtonStyle
            HStack(spacing: 6) {
                Image(systemName: "rectangle.stack.fill")
                    .foregroundStyle(.blue)
                Text("\(items.count) items selected")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(AdaptiveColors.overlayAuto(0.12)))

            
            Spacer()
            
            // Bulk action buttons
            HStack(spacing: 12) {
                // Paste All Button
                Button(action: onPasteAll) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard")
                        Text("Paste All")
                    }
                }
                .buttonStyle(DroppyAccentButtonStyle(color: AdaptiveColors.selectionBlueAuto, size: .medium))
                
                // Copy All Button
                Button(action: onCopyAll) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy All")
                    }
                }
                .buttonStyle(DroppyPillButtonStyle(size: .medium))
                
                // Save All Button
                Button(action: onSaveAll) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save All")
                    }
                }
                .buttonStyle(DroppyPillButtonStyle(size: .medium))
                
                // Delete All Button
                Button(action: onDeleteAll) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 40))
            }
        }
        .padding(DroppySpacing.xl)
    }
}

// MARK: - Stacked Card View

struct StackedCardView: View {
    let item: ClipboardItem
    let index: Int
    let totalCount: Int
    
    private var offset: CGFloat {
        CGFloat(index) * 8
    }
    
    private var rotation: Double {
        Double(index - totalCount / 2) * 3.0
    }
    
    private var scale: CGFloat {
        1.0 - CGFloat(index) * 0.05
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                    .fill(AdaptiveColors.overlayAuto(0.15))
                    .frame(width: 48, height: 48)
                
                Image(systemName: iconName(for: item.type))
                    .font(.system(size: 22))
                    .foregroundStyle(AdaptiveColors.primaryTextAuto)
            }
            
            // Title
            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AdaptiveColors.primaryTextAuto.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 100)
        }
        .padding(DroppySpacing.lg)
        .frame(width: 130, height: 120)
        .background(
            RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .droppyCardShadow()
        .scaleEffect(scale)
        .offset(x: offset, y: -offset)
        .rotationEffect(.degrees(rotation))
        .zIndex(Double(totalCount - index))
    }
    
    private func iconName(for type: ClipboardType) -> String {
        switch type {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .file: return "doc"
        case .url: return "link"
        case .color: return "paintpalette"
        }
    }
}

// MARK: - Window Drag Area
/// An NSViewRepresentable that enables window dragging when used as a background
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        return WindowDragNSView()
    }
    
    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}
class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
    
    override func mouseUp(with event: NSEvent) {
        // Consumed
    }
}

// MARK: - URL Preview Components

struct URLPreviewCard: View {
    let item: ClipboardItem
    let isLoading: Bool
    let isDirectImage: Bool
    let title: String?
    let description: String?
    let image: NSImage?
    let icon: NSImage?
    @State private var isHovering = false
    
    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView().controlSize(.regular)
                    Text("Fetching preview…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            } else {
                VStack(spacing: 0) {
                    // Main Image Area
                    ZStack {
                        if let previewImage = image {
                            Image(nsImage: previewImage)
                                .resizable()
                                .aspectRatio(contentMode: isDirectImage ? .fit : .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: isDirectImage ? 260 : 180)
                                .clipped()
                        } else {
                            Rectangle()
                                .fill(AdaptiveColors.overlayAuto(0.05))
                                .frame(height: isDirectImage ? 200 : 120)
                                .overlay {
                                    Image(systemName: isDirectImage ? "photo" : "link")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary.opacity(0.3))
                                }
                        }
                    }
                    .background(AdaptiveColors.overlayAuto(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
                    
                    MetadataInfoStrip(
                        item: item,
                        isDirectImage: isDirectImage,
                        title: title,
                        description: description,
                        icon: icon
                    )
                }
                .contentShape(Rectangle())
                .onHover { hovering in
                    isHovering = hovering
                }
                .onTapGesture {
                    if let urlString = item.content, let url = URL(string: urlString) {
                        NSWorkspace.shared.open(url)
                        ClipboardWindowController.shared.close()
                    }
                }
                .opacity(isHovering ? 0.8 : 1.0)
                .animation(DroppyAnimation.hoverQuick, value: isHovering)
                .help("Click to open link")
                
                // Raw URL at the bottom
                Text(item.content ?? "")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.blue.opacity(0.8))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
        }
    }
}

struct MetadataInfoStrip: View {
    let item: ClipboardItem
    let isDirectImage: Bool
    let title: String?
    let description: String?
    let icon: NSImage?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                // Favicon/Icon
                Group {
                    if let icon = icon {
                        Image(nsImage: icon)
                            .resizable()
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                            .background(AdaptiveColors.overlayAuto(0.05))
                    }
                }
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.ml, style: .continuous))
                
                VStack(alignment: .leading, spacing: 4) {
                    if let title = title {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AdaptiveColors.primaryTextAuto)
                            .lineLimit(2)
                    } else if isDirectImage, let url = URL(string: item.content ?? "") {
                        Text(url.lastPathComponent)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AdaptiveColors.primaryTextAuto)
                            .lineLimit(1)
                    }
                    
                    Text(description ?? "No description")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(.bottom, 4)
            
            Divider().background(AdaptiveColors.overlayAuto(0.1))
            
            // Domain Area
            HStack {
                if let urlString = item.content,
                   let domain = LinkPreviewService.shared.extractDomain(from: urlString) {
                    Label(domain, systemImage: "link")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Type Badge
                URLTypeBadge(isDirectImage: isDirectImage)
            }
            .padding(.top, 4)
        }
        .padding(DroppySpacing.lg)
        .background(AdaptiveColors.overlayAuto(0.03))
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
    }
}

struct URLTypeBadge: View {
    let isDirectImage: Bool
    
    var body: some View {
        Text(isDirectImage ? "Image Link" : "Website")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AdaptiveColors.primaryTextAuto)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background { Rectangle().fill(.ultraThinMaterial) }
            .background(AdaptiveColors.overlayAuto(0.2))
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.ml, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.ml, style: .continuous)
                    .stroke(AdaptiveColors.overlayAuto(0.25), lineWidth: 1)
            )
            .droppyCardShadow()
    }
}

// MARK: - Tag Filter Popover

struct TagFilterPopover: View {
    @Binding var selectedTagFilter: UUID?
    @Binding var showTagManagement: Bool
    @ObservedObject var manager: ClipboardManager
    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Filter by Tag")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    withAnimation(DroppyAnimation.transition) {
                        showTagManagement = true
                    }
                } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Manage Tags")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            // "All" option
            Button {
                selectedTagFilter = nil
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: selectedTagFilter == nil ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedTagFilter == nil ? .blue : .secondary)
                        .font(.system(size: 14))
                    Text("All Items")
                        .font(.system(size: 13))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(selectedTagFilter == nil ? Color.blue.opacity(0.15) : Color.clear)
            
            if !manager.tags.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                // Tag list
                ForEach(manager.tags) { tag in
                    Button {
                        selectedTagFilter = tag.id
                    } label: {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 10, height: 10)
                            Text(tag.name)
                                .font(.system(size: 13))
                            Spacer()
                            if selectedTagFilter == tag.id {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(selectedTagFilter == tag.id ? Color.blue.opacity(0.15) : Color.clear)
                }
            }
            
            if manager.tags.isEmpty {
                Text("No tags yet")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(DroppySpacing.md)
            }
        }
        .frame(width: 200)
        .background(useTransparentBackground ? AnyShapeStyle(.ultraThinMaterial) : AdaptiveColors.panelBackgroundOpaqueStyle)
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                .stroke(AdaptiveColors.overlayAuto(useTransparentBackground ? 0.14 : 0.08), lineWidth: 1)
        )
    }
}

// MARK: - Tag Management Sheet

struct TagManagementSheet: View {
    @ObservedObject var manager: ClipboardManager
    let onDone: () -> Void
    
    @State private var newTagName = ""
    @State private var selectedColorIndex = 0
    @State private var editingTag: ClipboardTag? = nil
    @State private var editingName = ""
    @State private var editingColorIndex = 0
    @FocusState private var isTextFieldFocused: Bool
    
    private var selectedColor: Color {
        Color(hex: ClipboardTag.presetColors[selectedColorIndex]) ?? .cyan
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(selectedColor)
                    .animation(.easeInOut(duration: 0.2), value: selectedColorIndex)
                
                Text("Manage Tags")
                    .font(.title2.bold())
                    .foregroundStyle(AdaptiveColors.primaryTextAuto)
            }
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
                .padding(.horizontal, 24)
            
            // Add new tag section
            VStack(spacing: 12) {
                // Name field - Styled like clipboard search
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(selectedColor)
                        .font(.system(size: 14))
                        .animation(.easeInOut(duration: 0.2), value: selectedColorIndex)
                    
                    TextField("New tag name…", text: $newTagName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AdaptiveColors.primaryTextAuto)
                        .focused($isTextFieldFocused)
                        .onSubmit { addTag() }
                    
                    Button {
                        newTagName = ""
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 20))
                    .opacity(newTagName.isEmpty ? 0 : 1)
                    .disabled(newTagName.isEmpty)
                }
                .droppyTextInputChrome(
                    cornerRadius: DroppyRadius.large,
                    horizontalPadding: 10,
                    verticalPadding: 8
                )
                
                // Color picker grid
                HStack(spacing: 8) {
                    ForEach(Array(ClipboardTag.presetColors.enumerated()), id: \.offset) { index, colorHex in
                        Circle()
                            .fill(Color(hex: colorHex) ?? .gray)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: selectedColorIndex == index ? 2 : 0)
                            )
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .opacity(selectedColorIndex == index ? 1 : 0)
                            )
                            .scaleEffect(selectedColorIndex == index ? 1.1 : 1.0)
                            .animation(DroppyAnimation.hover, value: selectedColorIndex)
                            .onTapGesture {
                                withAnimation(DroppyAnimation.hover) {
                                    selectedColorIndex = index
                                }
                            }
                    }
                }
                .padding(.vertical, 4)
                
                // Add button - DroppyPillButtonStyle
                Button {
                    addTag()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Tag")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(DroppyAccentButtonStyle(color: .accentColor, size: .small))
                .disabled(newTagName.isEmpty)
                .opacity(newTagName.isEmpty ? 0.5 : 1.0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            Divider()
                .padding(.horizontal, 24)
            
            // Tag list
            if manager.tags.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tag.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                    Text("No tags yet")
                        .font(.system(size: 13))
                        .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                    Text("Add a tag above to get started")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaptiveColors.secondaryTextAuto.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(manager.tags.enumerated()), id: \.element.id) { index, tag in
                            TagRowView(
                                tag: tag,
                                isEditing: editingTag?.id == tag.id,
                                editingName: $editingName,
                                editingColorIndex: $editingColorIndex,
                                onStartEdit: {
                                    withAnimation(DroppyAnimation.transition) {
                                        editingTag = tag
                                        editingName = tag.name
                                        editingColorIndex = ClipboardTag.presetColors.firstIndex(of: tag.colorHex) ?? 0
                                    }
                                },
                                onSaveEdit: {
                                    if !editingName.isEmpty {
                                        let newColorHex = ClipboardTag.presetColors[editingColorIndex]
                                        manager.updateTag(tag, name: editingName, colorHex: newColorHex)
                                    }
                                    withAnimation(DroppyAnimation.transition) {
                                        editingTag = nil
                                    }
                                },
                                onCancelEdit: {
                                    withAnimation(DroppyAnimation.transition) {
                                        editingTag = nil
                                    }
                                },
                                canMoveUp: index > 0,
                                canMoveDown: index < manager.tags.count - 1,
                                onMoveUp: {
                                    guard index > 0 else { return }
                                    withAnimation(DroppyAnimation.hover) {
                                        manager.reorderTags(from: index, to: index - 1)
                                    }
                                },
                                onMoveDown: {
                                    guard index < manager.tags.count - 1 else { return }
                                    withAnimation(DroppyAnimation.hover) {
                                        manager.reorderTags(from: index, to: index + 1)
                                    }
                                },
                                onDelete: {
                                    withAnimation(DroppyAnimation.transition) {
                                        manager.deleteTag(tag)
                                    }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                                removal: .scale(scale: 0.9).combined(with: .opacity)
                            ))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
            }
            
            Divider()
                .padding(.horizontal, 24)
            
            // Done button
            HStack {
                Spacer()
                Button {
                    onDone()
                } label: {
                    Text("Done")
                }
                .buttonStyle(DroppyAccentButtonStyle(color: .accentColor, size: .small))
            }
            .padding(DroppySpacing.lg)
        }
        .frame(width: 340, height: 630)
        .droppyTransparentBackground(true)
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                .stroke(AdaptiveColors.overlayAuto(0.14), lineWidth: 1)
        )
        .onExitCommand(perform: onDone)
    }
    
    private func addTag() {
        guard !newTagName.isEmpty else { return }
        let colorHex = ClipboardTag.presetColors[selectedColorIndex]
        withAnimation(DroppyAnimation.transition) {
            _ = manager.addTag(name: newTagName, colorHex: colorHex)
        }
        newTagName = ""
        // Cycle to next color
        selectedColorIndex = (selectedColorIndex + 1) % ClipboardTag.presetColors.count
    }
}

// MARK: - Tag Row View (for management)

struct TagRowView: View {
    let tag: ClipboardTag
    let isEditing: Bool
    @Binding var editingName: String
    @Binding var editingColorIndex: Int
    let onStartEdit: () -> Void
    let onSaveEdit: () -> Void
    let onCancelEdit: () -> Void
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovering = false
    @State private var isColorPickerPresented = false
    @State private var isHoveringColorSwatch = false
    @State private var isHoveringColorPopover = false
    @FocusState private var isEditFocused: Bool

    private var safeEditingColorIndex: Int {
        guard !ClipboardTag.presetColors.isEmpty else { return 0 }
        return min(max(editingColorIndex, 0), ClipboardTag.presetColors.count - 1)
    }

    private var selectedEditColor: Color {
        guard !ClipboardTag.presetColors.isEmpty else { return .gray }
        return Color(hex: ClipboardTag.presetColors[safeEditingColorIndex]) ?? .gray
    }
    
    var body: some View {
        HStack(spacing: 10) {
            if isEditing {
                // Editing mode - compact color button + full-width name field
                Button {
                    isColorPickerPresented.toggle()
                } label: {
                    Circle()
                        .fill(selectedEditColor)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.9), lineWidth: 1.8)
                        )
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 28))
                .help("Tag Color")
                .onHover { hovering in
                    isHoveringColorSwatch = hovering
                    if hovering {
                        isColorPickerPresented = true
                    } else {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                            if !isHoveringColorSwatch && !isHoveringColorPopover {
                                isColorPickerPresented = false
                            }
                        }
                    }
                }
                .droppyPopover(isPresented: $isColorPickerPresented, arrowEdge: .bottom) {
                    HStack(spacing: 6) {
                        ForEach(Array(ClipboardTag.presetColors.enumerated()), id: \.offset) { index, colorHex in
                            Button {
                                withAnimation(DroppyAnimation.hoverBouncy) {
                                    editingColorIndex = index
                                }
                                isColorPickerPresented = false
                            } label: {
                                Circle()
                                    .fill(Color(hex: colorHex) ?? .gray)
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Circle()
                                            .stroke(AdaptiveColors.overlayAuto(0.3), lineWidth: 0.8)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                safeEditingColorIndex == index ? AdaptiveColors.primaryTextAuto : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                    .droppyTransparentBackground(true)
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                            .stroke(AdaptiveColors.overlayAuto(0.2), lineWidth: 1)
                    )
                    .onHover { hovering in
                        isHoveringColorPopover = hovering
                        if !hovering {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                                if !isHoveringColorSwatch && !isHoveringColorPopover {
                                    isColorPickerPresented = false
                                }
                            }
                        }
                    }
                }
                
                TextField("Tag name", text: $editingName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AdaptiveColors.primaryTextAuto)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .focused($isEditFocused)
                    .droppyTextInputChrome(
                        cornerRadius: DroppyRadius.large,
                        horizontalPadding: 10,
                        verticalPadding: 6
                    )
                    .onSubmit { onSaveEdit() }
                    .onAppear { isEditFocused = true }
                
                Spacer()
                
                // Edit mode buttons - same positioning as display mode
                HStack(spacing: 6) {
                    Button {
                        onSaveEdit()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 26))
                    
                    Button {
                        onCancelEdit()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 26))
                }
                .frame(width: 60, alignment: .trailing)
            } else {
                // Normal display mode - capsule shaped row
                Circle()
                    .fill(tag.color)
                    .frame(width: 12, height: 12)
                
                Text(tag.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                Spacer()
                
                // Reorder controls
                HStack(spacing: 6) {
                    Button {
                        onMoveUp()
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 26))
                    .disabled(!canMoveUp)
                    .opacity(canMoveUp ? 1 : 0.35)
                    .help("Move Up")
                    
                    Button {
                        onMoveDown()
                    } label: {
                        Image(systemName: "arrow.down")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 26))
                    .disabled(!canMoveDown)
                    .opacity(canMoveDown ? 1 : 0.35)
                    .help("Move Down")
                }
                .frame(width: 60, alignment: .trailing)
                .opacity(isHovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .allowsHitTesting(isHovering)
                
                // Edit/delete actions
                HStack(spacing: 6) {
                    Button {
                        onStartEdit()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 26))
                    
                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(DroppyCircleButtonStyle(size: 26))
                }
                .frame(width: 60, alignment: .trailing)
                .opacity(isHovering ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
                .allowsHitTesting(isHovering)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(AdaptiveColors.overlayAuto(isHovering || isEditing ? 0.08 : 0.04))
        )
        .overlay(
            Capsule()
                .stroke(AdaptiveColors.overlayAuto(isHovering || isEditing ? 0.1 : 0.05), lineWidth: 1)
        )
        .contentShape(Capsule())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing {
                isColorPickerPresented = false
                isHoveringColorSwatch = false
                isHoveringColorPopover = false
            }
        }
    }
}
