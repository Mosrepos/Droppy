import SwiftUI

// MARK: - Extensions Shop
// Extracted from SettingsView.swift for faster incremental builds

struct ExtensionsShopView: View {
    private static var hasPrewarmedExtensionAssetsThisSession = false

    let selectedCategory: ExtensionCategory?
    @State private var extensionCounts: [String: Int] = [:]
    @State private var extensionStateVersion = 0
    @AppStorage(AppPreferenceKey.disableAnalytics) private var disableAnalytics = PreferenceDefault.disableAnalytics
    @AppStorage(AppPreferenceKey.pomodoroInstalled) private var isPomodoroInstalled = PreferenceDefault.pomodoroInstalled
    
    // MARK: - Installed State Checks
    private var isAIInstalled: Bool { AIInstallManager.shared.isInstalled }
    private var isAlfredInstalled: Bool { UserDefaults.standard.bool(forKey: "alfredTracked") }
    private var isFinderInstalled: Bool { UserDefaults.standard.bool(forKey: "finderTracked") }
    private var isSpotifyInstalled: Bool { UserDefaults.standard.bool(forKey: "spotifyTracked") }
    private var isAppleMusicInstalled: Bool { !ExtensionType.appleMusic.isRemoved }
    private var isElementCaptureInstalled: Bool {
        UserDefaults.standard.data(forKey: "elementCaptureShortcut") != nil
    }
    private var isWindowSnapInstalled: Bool { !WindowSnapManager.shared.shortcuts.isEmpty }
    private var isFFmpegInstalled: Bool { FFmpegInstallManager.shared.isInstalled }
    private var isVoiceTranscribeInstalled: Bool {
        VoiceTranscribeRuntimeManager.shared.isInstalled && VoiceTranscribeManager.shared.isModelDownloaded
    }
    private var isTerminalNotchInstalled: Bool { TerminalNotchManager.shared.isInstalled }
    private var isNotificationHUDInstalled: Bool { UserDefaults.standard.bool(forKey: AppPreferenceKey.notificationHUDInstalled) }
    private var isCaffeineInstalled: Bool { UserDefaults.standard.bool(forKey: AppPreferenceKey.caffeineInstalled) }
    private var isMenuBarManagerInstalled: Bool { MenuBarManager.shared.isEnabled }
    private var isTodoInstalled: Bool { UserDefaults.standard.bool(forKey: AppPreferenceKey.todoInstalled) }
    private var isCameraInstalled: Bool { UserDefaults.standard.bool(forKey: AppPreferenceKey.cameraInstalled) }

    init(selectedCategory: ExtensionCategory? = nil) {
        self.selectedCategory = selectedCategory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Extensions section content (filters + cards/rows)
            extensionsList
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(nil, value: extensionCounts)
        .animation(nil, value: extensionStateVersion)
        .onAppear {
            if !Self.hasPrewarmedExtensionAssetsThisSession {
                Self.hasPrewarmedExtensionAssetsThisSession = true
                let urls = extensionAssetPrewarmURLs
                Task {
                    await ExtensionIconCache.shared.prewarm(urls: urls)
                }
            }

            Task {
                guard !disableAnalytics else {
                    extensionCounts = [:]
                    return
                }
                async let countsTask = AnalyticsService.shared.fetchExtensionCounts()
                if let counts = try? await countsTask {
                    extensionCounts = counts
                }
            }
        }
        .onChange(of: disableAnalytics) { _, isDisabled in
            if isDisabled {
                extensionCounts = [:]
                return
            }

            Task {
                async let countsTask = AnalyticsService.shared.fetchExtensionCounts()
                if let counts = try? await countsTask {
                    extensionCounts = counts
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .extensionStateChanged)) { _ in
            extensionStateVersion += 1
        }
    }
    
    private var shouldShowEditorialFeaturedBlocks: Bool {
        selectedCategory == nil || selectedCategory == .all
    }

    private var editorialFeaturedBlockOneItems: [EditorialFeaturedItem] {
        [
            EditorialFeaturedItem(
                id: "menuBarManager-editorial",
                panelID: "menuBarManager",
                title: "Menu Bar Manager",
                subtitle: "Floating menu bar with Liquid Glass design",
                iconURL: "https://getdroppy.app/assets/icons/menubarmanager.png",
                imageURL: "https://getdroppy.app/assets/screenshots/menu-bar-manager.png",
                isInstalled: isMenuBarManagerInstalled
            ) {
                AnyView(MenuBarManagerInfoView(
                    installCount: extensionCounts["menuBarManager"],
                ))
            },
            EditorialFeaturedItem(
                id: "todo-editorial",
                panelID: "todo",
                title: "Reminders",
                subtitle: "Calendar + Reminders with natural language and instant join",
                iconURL: "https://getdroppy.app/assets/icons/reminders.png",
                imageURL: "https://getdroppy.app/assets/images/reminders-screenshot.gif",
                isInstalled: isTodoInstalled
            ) {
                AnyView(ToDoInfoView(
                    installCount: extensionCounts["todo"],
                ))
            },
        ]
    }

    private var editorialFeaturedBlockTwoItems: [EditorialFeaturedItem] {
        [
            EditorialFeaturedItem(
                id: "pomodoro-editorial",
                panelID: "pomodoro",
                title: "Pomodoro",
                subtitle: "Focus sessions, breaks, and momentum",
                iconURL: "https://getdroppy.app/assets/icons/pomodoro.png?v=20260221",
                imageURL: "https://getdroppy.app/assets/images/pomodoro-screenshot.png",
                isInstalled: isPomodoroInstalled
            ) {
                AnyView(PomodoroInfoView(
                    installCount: extensionCounts["pomodoro"],
                ))
            },
            EditorialFeaturedItem(
                id: "elementCapture-editorial",
                panelID: "elementCapture",
                title: "Element Capture",
                subtitle: "Full screenshot capture and editing",
                iconURL: "https://getdroppy.app/assets/icons/element-capture.jpg",
                imageURL: "https://getdroppy.app/assets/images/element-capture-screenshot.gif",
                isInstalled: isElementCaptureInstalled
            ) {
                AnyView(ElementCaptureInfoViewWrapper(
                    installCount: extensionCounts["elementCapture"],
                ))
            },
        ]
    }

    private var extensionAssetPrewarmURLs: [URL] {
        let extensionIconURLs = filteredExtensions
            .compactMap(\.iconURL)
            .compactMap(URL.init(string:))
        let editorialItems = editorialFeaturedBlockOneItems + editorialFeaturedBlockTwoItems
        let editorialImageURLs = editorialItems.compactMap { URL(string: $0.imageURL) }
        let editorialIconURLs = editorialItems.compactMap { URL(string: $0.iconURL) }
        return extensionIconURLs + editorialImageURLs + editorialIconURLs
    }
    
    // MARK: - Extensions List
    
    private var extensionsList: some View {
        VStack(alignment: .leading, spacing: 14) {
            let extensions = filteredExtensions
            if shouldShowEditorialFeaturedBlocks {
                EditorialFeaturedBlock(items: editorialFeaturedBlockOneItems)
                extensionsRows(items: Array(extensions.prefix(6)))
                EditorialFeaturedBlock(items: editorialFeaturedBlockTwoItems)
                if extensions.count > 6 {
                    extensionsRows(items: Array(extensions.dropFirst(6)))
                }
            } else {
                extensionsRows(items: extensions)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func extensionsRows(items: [ExtensionListItem]) -> some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let leftColumn = stride(from: 0, to: items.count, by: 2).map { items[$0] }
            let rightColumn = stride(from: 1, to: items.count, by: 2).map { items[$0] }

            HStack(alignment: .top, spacing: 20) {
                extensionsColumn(items: leftColumn)
                extensionsColumn(items: rightColumn)
            }
        }
    }

    @ViewBuilder
    private func extensionsColumn(items: [ExtensionListItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.1.id) { index, ext in
                CompactExtensionRow(
                    iconURL: ext.iconURL,
                    iconPlaceholder: ext.iconPlaceholder,
                    iconPlaceholderColor: ext.iconPlaceholderColor,
                    title: ext.title,
                    subtitle: ext.subtitle,
                    categoryLabel: ext.category.rawValue,
                    panelID: ext.id,
                    isInstalled: ext.isInstalled,
                    isDisabled: ext.extensionType.isRemoved,
                    installCount: extensionCounts[ext.analyticsKey],
                    isCommunity: ext.isCommunity,
                    onEnableAction: {
                        enableExtension(ext.extensionType)
                    }
                ) {
                    ext.detailView()
                }
                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 78)
                        .padding(.trailing, 8)
                        .opacity(0.42)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    
    // MARK: - Filtered Extensions
    
    private var filteredExtensions: [ExtensionListItem] {
        let _ = extensionStateVersion
        let allExtensions: [ExtensionListItem] = [
            // AI Extensions
            ExtensionListItem(
                id: "aiBackgroundRemoval",
                iconURL: "https://getdroppy.app/assets/icons/ai-bg.jpg",
                title: "AI Background Removal",
                subtitle: "Remove backgrounds instantly",
                category: .ai,
                isInstalled: isAIInstalled,
                analyticsKey: "aiBackgroundRemoval",
                extensionType: .aiBackgroundRemoval
            ) {
                AnyView(AIInstallView(
                    installCount: extensionCounts["aiBackgroundRemoval"],
                ))
            },
            ExtensionListItem(
                id: "voiceTranscribe",
                iconURL: "https://getdroppy.app/assets/icons/voice-transcribe.jpg",
                title: "Voice Transcribe",
                subtitle: "Speech to text with AI",
                category: .ai,
                isInstalled: isVoiceTranscribeInstalled,
                analyticsKey: "voiceTranscribe",
                extensionType: .voiceTranscribe
            ) {
                AnyView(VoiceTranscribeInfoView(
                    installCount: extensionCounts["voiceTranscribe"],
                ))
            },
            // Media Extensions
            ExtensionListItem(
                id: "ffmpegVideoCompression",
                iconURL: "https://getdroppy.app/assets/icons/targeted-video-size.jpg",
                title: "Video Target Size",
                subtitle: "Compress videos to size",
                category: .media,
                isInstalled: isFFmpegInstalled,
                analyticsKey: "ffmpegVideoCompression",
                extensionType: .ffmpegVideoCompression
            ) {
                AnyView(FFmpegInstallView(
                    installCount: extensionCounts["ffmpegVideoCompression"],
                ))
            },
            // Productivity Extensions
            ExtensionListItem(
                id: "alfred",
                iconURL: "https://getdroppy.app/assets/icons/alfred.png",
                title: "Alfred Workflow",
                subtitle: "Push files via keyboard",
                category: .productivity,
                isInstalled: isAlfredInstalled,
                analyticsKey: "alfred",
                extensionType: .alfred
            ) {
                AnyView(ExtensionInfoView(
                    extensionType: .alfred,
                    onAction: {
                        if let path = Bundle.main.path(forResource: "Droppy", ofType: "alfredworkflow") {
                            NSWorkspace.shared.open(URL(fileURLWithPath: path))
                        }
                    },
                    installCount: extensionCounts["alfred"],
                ))
            },
            ExtensionListItem(
                id: "elementCapture",
                iconURL: "https://getdroppy.app/assets/icons/element-capture.jpg",
                title: "Element Capture",
                subtitle: "Full screenshot capture and editing",
                category: .productivity,
                isInstalled: isElementCaptureInstalled,
                analyticsKey: "elementCapture",
                extensionType: .elementCapture
            ) {
                AnyView(ElementCaptureInfoViewWrapper(
                    installCount: extensionCounts["elementCapture"],
                ))
            },
            ExtensionListItem(
                id: "finder",
                iconURL: "https://getdroppy.app/assets/icons/finder.png",
                title: "Finder Services",
                subtitle: "Right-click integration",
                category: .productivity,
                isInstalled: isFinderInstalled,
                analyticsKey: "finder",
                extensionType: .finder
            ) {
                AnyView(ExtensionInfoView(
                    extensionType: .finder,
                    onAction: {
                        _ = openFinderServicesSettings()
                    },
                    installCount: extensionCounts["finder"],
                ))
            },
            ExtensionListItem(
                id: "spotify",
                iconURL: "https://getdroppy.app/assets/icons/spotify.png",
                title: "Spotify Integration",
                subtitle: "Control music playback",
                category: .media,
                isInstalled: isSpotifyInstalled,
                analyticsKey: "spotify",
                extensionType: .spotify
            ) {
                AnyView(ExtensionInfoView(
                    extensionType: .spotify,
                    onAction: {
                        if let url = URL(string: "spotify://") {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    installCount: extensionCounts["spotify"],
                ))
            },
            ExtensionListItem(
                id: "appleMusic",
                iconURL: "https://getdroppy.app/assets/icons/apple-music.png",
                title: "Apple Music",
                subtitle: "Native music controls",
                category: .media,
                isInstalled: isAppleMusicInstalled,
                analyticsKey: "appleMusic",
                extensionType: .appleMusic
            ) {
                AnyView(ExtensionInfoView(
                    extensionType: .appleMusic,
                    onAction: {
                        // Open Apple Music app (similar to Spotify pattern)
                        if let url = URL(string: "music://") {
                            NSWorkspace.shared.open(url)
                        }
                        AppleMusicController.shared.refreshState()
                    },
                    installCount: extensionCounts["appleMusic"],
                ))
            },
            ExtensionListItem(
                id: "windowSnap",
                iconURL: "https://getdroppy.app/assets/icons/window-snap.jpg",
                title: "Window Snap",
                subtitle: "Snap with shortcuts",
                category: .productivity,
                isInstalled: isWindowSnapInstalled,
                analyticsKey: "windowSnap",
                extensionType: .windowSnap
            ) {
                AnyView(WindowSnapInfoView(
                    installCount: extensionCounts["windowSnap"],
                ))
            },
            ExtensionListItem(
                id: "terminalNotch",
                iconURL: "https://getdroppy.app/assets/icons/terminotch.jpg",
                title: "Termi-Notch",
                subtitle: "Quick terminal access",
                category: .productivity,
                isInstalled: isTerminalNotchInstalled,
                analyticsKey: "terminalNotch",
                extensionType: .terminalNotch
            ) {
                AnyView(TerminalNotchInfoView(
                    installCount: extensionCounts["terminalNotch"],
                ))
            },
            ExtensionListItem(
                id: "camera",
                iconURL: "https://getdroppy.app/assets/icons/snap-camera-v2.png",
                title: "Notchface",
                subtitle: "Live notch camera preview",
                category: .productivity,
                isInstalled: isCameraInstalled,
                analyticsKey: "camera",
                extensionType: .camera
            ) {
                AnyView(CameraInfoView(
                    installCount: extensionCounts["camera"],
                ))
            },
            ExtensionListItem(
                id: "quickshare",
                iconURL: "https://getdroppy.app/assets/icons/quickshare.jpg",
                title: "Droppy Quickshare",
                subtitle: "Share files via 0x0.st",
                category: .productivity,
                isInstalled: !ExtensionType.quickshare.isRemoved,
                analyticsKey: "quickshare",
                extensionType: .quickshare
            ) {
                AnyView(QuickshareInfoView(
                    installCount: extensionCounts["quickshare"],
                ))
            },
            ExtensionListItem(
                id: "notificationHUD",
                iconURL: "https://getdroppy.app/assets/icons/notification-hud.png",
                title: "Notify me!",
                subtitle: "Show notifications in notch",
                category: .productivity,
                isInstalled: isNotificationHUDInstalled,
                analyticsKey: "notificationHUD",
                extensionType: .notificationHUD,
                isCommunity: true
            ) {
                AnyView(NotificationHUDInfoView())
            },
            ExtensionListItem(
                id: "caffeine",
                iconURL: "https://getdroppy.app/assets/icons/high-alert.jpg",
                title: "High Alert",
                subtitle: "Keep your Mac awake",
                category: .productivity,
                isInstalled: isCaffeineInstalled,
                analyticsKey: "caffeine",
                extensionType: .caffeine,
                isCommunity: true
            ) {
                AnyView(CaffeineInfoView(
                    installCount: extensionCounts["caffeine"],
                ))
            },
            ExtensionListItem(
                id: "menuBarManager",
                iconURL: "https://getdroppy.app/assets/icons/menubarmanager.png",
                title: "Menu Bar Manager",
                subtitle: "Floating menu bar with Liquid Glass design",
                category: .productivity,
                isInstalled: isMenuBarManagerInstalled,
                analyticsKey: "menuBarManager",
                extensionType: .menuBarManager
            ) {
                AnyView(MenuBarManagerInfoView(
                    installCount: extensionCounts["menuBarManager"],
                ))
            },
            ExtensionListItem(
                id: "pomodoro",
                iconURL: "https://getdroppy.app/assets/icons/pomodoro.png?v=20260221",
                title: "Pomodoro",
                subtitle: "Focus sessions, breaks, and momentum",
                category: .productivity,
                isInstalled: isPomodoroInstalled,
                analyticsKey: "pomodoro",
                extensionType: .pomodoro
            ) {
                AnyView(PomodoroInfoView(
                    installCount: extensionCounts["pomodoro"],
                ))
            },
            ExtensionListItem(
                id: "todo",
                iconURL: "https://getdroppy.app/assets/icons/reminders.png",
                title: "Reminders",
                subtitle: "Calendar + Reminders with natural language and instant join",
                category: .productivity,
                isInstalled: isTodoInstalled,
                analyticsKey: "todo",
                extensionType: .todo,
                isCommunity: true
            ) {
                AnyView(ToDoInfoView(
                    installCount: extensionCounts["todo"],
                ))
            },
        ]
        
        // nil = show all, otherwise filter by category
        guard let category = selectedCategory else {
            return allExtensions.sorted { $0.title < $1.title }
        }
        
        switch category {
        case .all:
            return allExtensions.sorted { $0.title < $1.title }
        case .installed:
            return allExtensions.filter { $0.isInstalled && !$0.extensionType.isRemoved }.sorted { $0.title < $1.title }
        default:
            return allExtensions.filter { $0.category == category && !$0.extensionType.isRemoved }.sorted { $0.title < $1.title }
        }
    }

    private func enableExtension(_ extensionType: ExtensionType) {
        extensionType.setRemoved(false)

        switch extensionType {
        case .windowSnap:
            WindowSnapManager.shared.loadAndStartMonitoring()
        case .elementCapture:
            ElementCaptureManager.shared.loadAndStartMonitoring()
        case .aiBackgroundRemoval:
            AIInstallManager.shared.checkInstallationStatus()
        case .spotify:
            SpotifyController.shared.refreshState()
        case .appleMusic:
            AppleMusicController.shared.refreshState()
        case .notificationHUD:
            NotificationHUDManager.shared.startMonitoring()
        case .menuBarManager:
            MenuBarManager.shared.enable()
        default:
            break
        }

        AnalyticsService.shared.trackExtensionActivation(extensionId: extensionType.rawValue)
        NotificationCenter.default.post(name: .extensionStateChanged, object: extensionType)
    }
}

// MARK: - Extension List Item Model

private struct ExtensionListItem: Identifiable {
    let id: String
    let iconURL: String?
    let iconPlaceholder: String?
    let iconPlaceholderColor: Color?
    let title: String
    let subtitle: String
    let category: ExtensionCategory
    let isInstalled: Bool
    let analyticsKey: String
    let extensionType: ExtensionType
    var isCommunity: Bool = false
    let detailView: () -> AnyView

    init(
        id: String,
        iconURL: String? = nil,
        iconPlaceholder: String? = nil,
        iconPlaceholderColor: Color? = nil,
        title: String,
        subtitle: String,
        category: ExtensionCategory,
        isInstalled: Bool,
        analyticsKey: String,
        extensionType: ExtensionType,
        isCommunity: Bool = false,
        detailView: @escaping () -> AnyView
    ) {
        self.id = id
        self.iconURL = iconURL
        self.iconPlaceholder = iconPlaceholder
        self.iconPlaceholderColor = iconPlaceholderColor
        self.title = title
        self.subtitle = subtitle
        self.category = category
        self.isInstalled = isInstalled
        self.analyticsKey = analyticsKey
        self.extensionType = extensionType
        self.isCommunity = isCommunity
        self.detailView = detailView
    }
}

private struct EditorialFeaturedItem: Identifiable {
    let id: String
    let panelID: String
    let title: String
    let subtitle: String
    let iconURL: String
    let imageURL: String
    let isInstalled: Bool
    let detailView: () -> AnyView
}

private struct EditorialFeaturedBlock: View {
    let items: [EditorialFeaturedItem]
    private let cardHeight: CGFloat = EditorialFeaturedCard.layout.cardHeight
    private let columnSpacing: CGFloat = 20
    private let rowSpacing: CGFloat = 14

    private var leftColumnItems: [EditorialFeaturedItem] {
        stride(from: 0, to: items.count, by: 2).map { items[$0] }
    }

    private var rightColumnItems: [EditorialFeaturedItem] {
        stride(from: 1, to: items.count, by: 2).map { items[$0] }
    }

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            editorialColumn(items: leftColumnItems)
            editorialColumn(items: rightColumnItems)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func editorialColumn(items: [EditorialFeaturedItem]) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(items) { item in
                EditorialFeaturedCard(item: item)
                    .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct EditorialFeaturedCard: View {
    let item: EditorialFeaturedItem
    @State private var isActionHovering = false

    fileprivate struct layout {
        static let cardHeight: CGFloat = 300
        static let mediaHeight: CGFloat = 152
        static let iconSize: CGFloat = 44
        static let iconInset: CGFloat = 12
        static let contentHorizontalInset: CGFloat = 12
        static let contentTopInset: CGFloat = 12
        static let contentBottomInset: CGFloat = 12
        static let titleSlotHeight: CGFloat = 24
        static let subtitleSlotHeight: CGFloat = 42
    }

    private var actionTitle: String {
        item.isInstalled ? "Manage" : "Get"
    }

    var body: some View {
        Button {
            ExtensionDetailWindowController.shared.present(
                id: item.panelID,
                parent: SettingsWindowController.shared.activeSettingsWindow
            ) {
                item.detailView()
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    GeometryReader { geometry in
                        let mediaSize = geometry.size

                        CachedAsyncImage(url: URL(string: item.imageURL)) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: mediaSize.width, height: mediaSize.height, alignment: .center)
                                .clipped()
                        } placeholder: {
                            Rectangle()
                                .fill(AdaptiveColors.overlayAuto(0.08))
                                .frame(width: mediaSize.width, height: mediaSize.height, alignment: .center)
                                .clipped()
                        }
                    }

                    LinearGradient(
                        colors: [Color.clear, AdaptiveColors.panelBackgroundAuto.opacity(0.74)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    CachedAsyncImage(url: URL(string: item.iconURL)) { image in
                        image.droppyExtensionIcon(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous)
                            .fill(AdaptiveColors.overlayAuto(0.1))
                    }
                    .frame(width: layout.iconSize, height: layout.iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous))
                    .droppyCardShadow(opacity: 0.28)
                    .padding(layout.iconInset)
                }
                .frame(height: layout.mediaHeight)
                .clipped()

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AdaptiveColors.primaryTextAuto)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, minHeight: layout.titleSlotHeight, maxHeight: layout.titleSlotHeight, alignment: .topLeading)

                    Text(item.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, minHeight: layout.subtitleSlotHeight, maxHeight: layout.subtitleSlotHeight, alignment: .topLeading)

                    Spacer(minLength: 0)

                    HStack {
                        Text(actionTitle)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(isActionHovering ? 1.0 : 0.92))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(AdaptiveColors.overlayAuto(0.12), lineWidth: 1)
                            )
                            .scaleEffect(isActionHovering ? 1.02 : 1.0)
                            .animation(DroppyAnimation.hoverQuick, value: isActionHovering)
                            .onHover { hovering in
                                isActionHovering = hovering
                            }
                        Spacer()
                    }
                }
                .padding(.horizontal, layout.contentHorizontalInset)
                .padding(.top, layout.contentTopInset)
                .padding(.bottom, layout.contentBottomInset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [AdaptiveColors.panelBackgroundAuto, AdaptiveColors.overlayAuto(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.lx, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.lx, style: .continuous)
                    .strokeBorder(AdaptiveColors.overlayAuto(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(EditorialFeaturedCardButtonStyle())
        .frame(height: layout.cardHeight, alignment: .topLeading)
    }
}

private struct EditorialFeaturedCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(DroppyAnimation.hoverQuick, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: DroppyRadius.lx, style: .continuous))
    }
}

// MARK: - Featured Extension Card (Large)

struct FeaturedExtensionCard<DetailView: View>: View {
    let panelID: String
    let category: String
    let title: String
    let subtitle: String
    let iconURL: String
    let screenshotURL: String?
    let accentColor: Color
    let isInstalled: Bool
    var installCount: Int?
    let detailView: () -> DetailView
    
    @State private var isHovering = false

    private var titleColor: Color {
        AdaptiveColors.primaryTextAuto
    }

    private var subtitleColor: Color {
        AdaptiveColors.secondaryTextAuto
    }

    private var statTextColor: Color {
        AdaptiveColors.secondaryTextAuto.opacity(0.82)
    }

    private var actionTextColor: Color {
        AdaptiveColors.primaryTextAuto
    }

    private var actionBackgroundColor: Color {
        accentColor.opacity(0.24)
    }

    private var screenshotOpacity: Double {
        0.2
    }

    private var screenshotFade: LinearGradient {
        return LinearGradient(
            stops: [
                .init(color: AdaptiveColors.panelBackgroundAuto.opacity(0.98), location: 0.0),
                .init(color: AdaptiveColors.panelBackgroundAuto.opacity(0.94), location: 0.45),
                .init(color: AdaptiveColors.panelBackgroundAuto.opacity(0.72), location: 0.65),
                .init(color: Color.clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var cardBackground: LinearGradient {
        return LinearGradient(
            colors: [AdaptiveColors.panelBackgroundAuto, AdaptiveColors.overlayAuto(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        Button {
            ExtensionDetailWindowController.shared.present(
                id: panelID,
                parent: SettingsWindowController.shared.activeSettingsWindow
            ) {
                detailView()
            }
        } label: {
            ZStack(alignment: .leading) {
                // Screenshot background on right side with fade
                if let screenshotURLString = screenshotURL,
                   let url = URL(string: screenshotURLString) {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            Spacer()
                            
                            CachedAsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width * 0.6, height: geometry.size.height)
                                    .clipped()
                            } placeholder: {
                                Color.clear
                            }
                        }
                    }
                    .opacity(screenshotOpacity)
                    
                    // Gradient fade from left to blend the screenshot
                    screenshotFade
                }
                
                // Content overlay
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Category label (only show if not empty)
                        if !category.isEmpty {
                            Text(category)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(accentColor.opacity(0.9))
                                .tracking(0.5)
                        }
                        
                        // Title
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        
                        // Subtitle
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .allowsTightening(true)
                        
                        Spacer()
                        
                        // Setup/Manage Button
                        HStack(spacing: 12) {
                            Text(isInstalled ? "Manage" : "Set Up")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(actionTextColor)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous)
                                        .fill(actionBackgroundColor)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous)
                                        .stroke(AdaptiveColors.overlayAuto(0.1), lineWidth: 1)
                                )
                            
                            if let count = installCount, count > 0 {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 10))
                                    Text("\(count)")
                                        .font(.caption2.weight(.medium))
                                }
                                .foregroundStyle(statTextColor)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Icon
                    CachedAsyncImage(url: URL(string: iconURL)) { image in
                        image.droppyExtensionIcon(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: DroppyRadius.large)
                            .fill(AdaptiveColors.overlayAuto(0.1))
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.lx, style: .continuous))
                    .droppyCardShadow(opacity: 0.4)
                }
                .padding(DroppySpacing.xl)
            }
            .frame(height: 160)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.xl, style: .continuous)
                    .stroke(AdaptiveColors.overlayAuto(0.16), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .animation(DroppyAnimation.hoverBouncy, value: isHovering)
        }
        .buttonStyle(DroppyCardButtonStyle(cornerRadius: DroppyRadius.xl))
        .onHover { hovering in
            isHovering = hovering
        }
    }
}


// MARK: - Featured Extension Card (Wide)

struct FeaturedExtensionCardWide<DetailView: View>: View {
    let panelID: String
    let title: String
    let subtitle: String
    let iconURL: String
    let screenshotURL: String?
    let accentColor: Color
    let isInstalled: Bool
    let features: [String]
    var isNew: Bool = false
    var badgeText: String? = nil
    let detailView: () -> DetailView
    
    @State private var isHovering = false

    private var titleColor: Color {
        AdaptiveColors.primaryTextAuto
    }

    private var subtitleColor: Color {
        AdaptiveColors.secondaryTextAuto
    }

    private var featureColor: Color {
        AdaptiveColors.primaryTextAuto.opacity(0.88)
    }

    private var screenshotFade: LinearGradient {
        return LinearGradient(
            stops: [
                .init(color: AdaptiveColors.panelBackgroundAuto.opacity(0.98), location: 0.0),
                .init(color: AdaptiveColors.panelBackgroundAuto.opacity(0.94), location: 0.45),
                .init(color: AdaptiveColors.panelBackgroundAuto.opacity(0.72), location: 0.65),
                .init(color: Color.clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var cardBackground: LinearGradient {
        return LinearGradient(
            colors: [AdaptiveColors.panelBackgroundAuto, AdaptiveColors.overlayAuto(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        Button {
            ExtensionDetailWindowController.shared.present(
                id: panelID,
                parent: SettingsWindowController.shared.activeSettingsWindow
            ) {
                detailView()
            }
        } label: {
            ZStack(alignment: .leading) {
                // Screenshot background on right side with fade
                if let screenshotURLString = screenshotURL,
                   let url = URL(string: screenshotURLString) {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            Spacer()
                            
                            CachedAsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width * 0.6, height: geometry.size.height)
                                    .clipped()
                            } placeholder: {
                                Color.clear
                            }
                        }
                    }
                    .opacity(0.2)
                    
                    // Gradient fade from left
                    screenshotFade
                }
                
                // Content overlay
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Title with optional badge
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(titleColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            
                            if let badgeText {
                                Text(badgeText)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.cyan.opacity(0.9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.cyan.opacity(0.15)))
                            } else if isNew {
                                Text("New")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.cyan.opacity(0.9))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.cyan.opacity(0.15)))
                            }
                        }
                        
                        // Subtitle
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(subtitleColor)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .allowsTightening(true)
                        
                        // Feature badges
                        HStack(spacing: 8) {
                            ForEach(features, id: \.self) { feature in
                                Text(feature)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(featureColor)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(AdaptiveColors.overlayAuto(0.08))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(AdaptiveColors.overlayAuto(0.12), lineWidth: 1)
                                    )
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Icon
                    CachedAsyncImage(url: URL(string: iconURL)) { image in
                        image.droppyExtensionIcon(contentMode: .fill)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: DroppyRadius.large)
                            .fill(AdaptiveColors.overlayAuto(0.1))
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
                    .droppyCardShadow(opacity: 0.4)
                }
                .padding(DroppySpacing.xl)
            }
            .frame(height: 120)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.lx, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.lx, style: .continuous)
                    .stroke(AdaptiveColors.overlayAuto(0.16), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .animation(DroppyAnimation.hoverBouncy, value: isHovering)
        }
        .buttonStyle(DroppyCardButtonStyle(cornerRadius: DroppyRadius.lx))
        .onHover { hovering in
            isHovering = hovering
        }
    }
}


// MARK: - Featured Extension Card (Compact)

struct FeaturedExtensionCardCompact<DetailView: View>: View {
    let panelID: String
    let category: String
    let title: String
    let subtitle: String
    let iconURL: String?
    var iconPlaceholder: String? = nil
    var iconPlaceholderColor: Color = .blue
    let screenshotURL: String?
    let accentColor: Color
    let isInstalled: Bool
    var isNew: Bool = false
    var isCommunity: Bool = false
    let detailView: () -> DetailView
    
    @State private var isHovering = false

    private var titleColor: Color {
        AdaptiveColors.primaryTextAuto
    }

    private var subtitleColor: Color {
        AdaptiveColors.secondaryTextAuto
    }

    private var screenshotFade: LinearGradient {
        return LinearGradient(
            stops: [
                .init(color: AdaptiveColors.panelBackgroundAuto.opacity(0.98), location: 0.0),
                .init(color: AdaptiveColors.panelBackgroundAuto.opacity(0.94), location: 0.4),
                .init(color: AdaptiveColors.panelBackgroundAuto.opacity(0.72), location: 0.65),
                .init(color: Color.clear, location: 1.0)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var cardBackground: LinearGradient {
        return LinearGradient(
            colors: [AdaptiveColors.panelBackgroundAuto, AdaptiveColors.overlayAuto(0.04)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        Button {
            ExtensionDetailWindowController.shared.present(
                id: panelID,
                parent: SettingsWindowController.shared.activeSettingsWindow
            ) {
                detailView()
            }
        } label: {
            ZStack(alignment: .leading) {
                // Screenshot background on right side with fade
                if let screenshotURLString = screenshotURL,
                   let url = URL(string: screenshotURLString) {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            Spacer()
                            
                            CachedAsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geometry.size.width * 0.7, height: geometry.size.height)
                                    .clipped()
                            } placeholder: {
                                Color.clear
                            }
                        }
                    }
                    .opacity(0.16)
                    
                    // Gradient fade from left
                    screenshotFade
                }
                
                // Content overlay
                VStack(alignment: .leading, spacing: 8) {
                    // Icon row (top right)
                    HStack {
                        Spacer()
                        
                        if let iconURL, let iconURLValue = URL(string: iconURL) {
                            CachedAsyncImage(url: iconURLValue) { image in
                                image.droppyExtensionIcon(contentMode: .fill)
                            } placeholder: {
                                Circle().fill(AdaptiveColors.overlayAuto(0.1))
                            }
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous))
                            .droppyCardShadow(opacity: 0.3)
                        } else if let iconPlaceholder {
                            Image(systemName: iconPlaceholder)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(iconPlaceholderColor)
                                .frame(width: 36, height: 36)
                                .background(iconPlaceholderColor.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous))
                                .droppyCardShadow(opacity: 0.3)
                        } else {
                            Circle()
                                .fill(AdaptiveColors.overlayAuto(0.1))
                                .frame(width: 36, height: 36)
                        }
                    }
                    
                    Spacer()
                    
                    // Title with optional badges
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        if isNew {
                            Text("New")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.cyan.opacity(0.9))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.cyan.opacity(0.15)))
                        }
                    }
                    
                    // Subtitle
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DroppySpacing.mdl)
                
                // Category ribbon badge in top-left corner (only for non-community categories)
                if !category.isEmpty && category != "COMMUNITY" {
                    VStack {
                        HStack {
                            Text(category)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AdaptiveColors.primaryTextAuto)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(accentColor.opacity(0.25))
                                )
                                .droppyCardShadow(opacity: 0.3)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(DroppySpacing.smd)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                    .stroke(AdaptiveColors.overlayAuto(0.16), lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(DroppyAnimation.hoverBouncy, value: isHovering)
        }
        .buttonStyle(DroppyCardButtonStyle(cornerRadius: DroppyRadius.large))
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Compact Extension Row

struct CompactExtensionRow<DetailView: View>: View {
    let iconURL: String?
    var iconPlaceholder: String? = nil
    var iconPlaceholderColor: Color? = nil
    let title: String
    let subtitle: String
    let categoryLabel: String
    let panelID: String
    let isInstalled: Bool
    var isDisabled: Bool = false
    var installCount: Int?
    var isCommunity: Bool = false
    var onEnableAction: (() -> Void)? = nil
    let detailView: () -> DetailView
    @State private var isActionHovering = false

    private var actionTitle: String {
        isDisabled ? "Disabled" : (isInstalled ? "Manage" : "Get")
    }

    private var headerText: String {
        isCommunity ? "Community Extension" : categoryLabel
    }

    private var actionTextColor: Color {
        isDisabled ? AdaptiveColors.secondaryTextAuto.opacity(0.88) : .blue
    }

    private var actionFill: Color {
        isDisabled ? AdaptiveColors.overlayAuto(0.08) : Color.white.opacity(0.92)
    }

    var body: some View {
        Button {
            ExtensionDetailWindowController.shared.present(
                id: panelID,
                parent: SettingsWindowController.shared.activeSettingsWindow
            ) {
                detailView()
            }
        } label: {
            HStack(alignment: .top, spacing: 14) {
                // Icon
                if let urlString = iconURL, let url = URL(string: urlString) {
                    CachedAsyncImage(url: url) { image in
                        image.droppyExtensionIcon(contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: DroppyRadius.ms)
                            .fill(AdaptiveColors.overlayAuto(0.1))
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous))
                    .saturation(isDisabled ? 0 : 1)
                    .opacity(isDisabled ? 0.65 : 1)
                } else if let placeholder = iconPlaceholder {
                    Image(systemName: placeholder)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(iconPlaceholderColor ?? .blue)
                        .frame(width: 56, height: 56)
                        .background((iconPlaceholderColor ?? .blue).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous))
                        .saturation(isDisabled ? 0 : 1)
                        .opacity(isDisabled ? 0.65 : 1)
                } else {
                    RoundedRectangle(cornerRadius: DroppyRadius.ms)
                        .fill(AdaptiveColors.overlayAuto(0.1))
                        .frame(width: 56, height: 56)
                        .opacity(isDisabled ? 0.65 : 1)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(headerText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.secondaryTextAuto)
                        .lineLimit(1)

                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isDisabled ? AdaptiveColors.secondaryTextAuto : AdaptiveColors.primaryTextAuto)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    
                    Text(subtitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(isDisabled ? AdaptiveColors.secondaryTextAuto : AdaptiveColors.secondaryTextAuto.opacity(0.92))
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34, alignment: .topLeading)

                    Text(actionTitle)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(actionTextColor)
                        .frame(minWidth: 84)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isDisabled ? actionFill : Color.white.opacity(isActionHovering ? 1.0 : 0.92))
                        )
                        .overlay(
                            Capsule()
                                .stroke(AdaptiveColors.overlayAuto(0.12), lineWidth: 1)
                        )
                        .scaleEffect(isActionHovering ? 1.02 : 1.0)
                        .animation(DroppyAnimation.hoverQuick, value: isActionHovering)
                        .onHover { hovering in
                            isActionHovering = hovering
                        }
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ExtensionRowButtonStyle())
        .contextMenu {
            if isDisabled {
                Button {
                    onEnableAction?()
                } label: {
                    Label("Enable Extension", systemImage: "power.circle.fill")
                }
            }
        }
        .opacity(isDisabled ? 0.78 : 1)
    }
}

private struct ExtensionRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(DroppyAnimation.hoverQuick, value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
    }
}

// MARK: - Category Pill Button

struct CategoryPillButton: View {
    let category: ExtensionCategory
    let isSelected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(category.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.blue.opacity(0.9))
                        .matchedGeometryEffect(id: "SelectedCategory", in: namespace)
                } else {
                    Capsule()
                        .fill(AdaptiveColors.buttonBackgroundAuto)
                }
            }
            .overlay(
                Capsule()
                    .stroke(isSelected ? AdaptiveColors.overlayAuto(0.15) : AdaptiveColors.overlayAuto(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(DroppySelectableButtonStyle(isSelected: isSelected))
    }
}

// MARK: - Legacy Card Styles (kept for compatibility)

struct ExtensionCardStyle: ViewModifier {
    let accentColor: Color
    @State private var isHovering = false
    
    private var borderColor: Color {
        if isHovering {
            return accentColor.opacity(0.7)
        } else {
            return AdaptiveColors.overlayAuto(0.1)
        }
    }
    
    func body(content: Content) -> some View {
        content
            .padding(DroppySpacing.lg)
            .background(AdaptiveColors.overlayAuto(0.05))
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(DroppyAnimation.hoverBouncy, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func extensionCardStyle(accentColor: Color) -> some View {
        modifier(ExtensionCardStyle(accentColor: accentColor))
    }
}

struct AIExtensionCardStyle: ViewModifier {
    @State private var isHovering = false
    
    func body(content: Content) -> some View {
        content
            .padding(DroppySpacing.lg)
            .background(AdaptiveColors.overlayAuto(0.05))
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                    .stroke(
                        isHovering
                            ? AnyShapeStyle(LinearGradient(
                                colors: [.purple.opacity(0.8), .pink.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            : AnyShapeStyle(AdaptiveColors.overlayAuto(0.1)),
                        lineWidth: 1
                    )
            )
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .animation(DroppyAnimation.hoverBouncy, value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

extension View {
    func aiExtensionCardStyle() -> some View {
        modifier(AIExtensionCardStyle())
    }
}

// MARK: - AI Extension Icon

struct AIExtensionIcon: View {
    var size: CGFloat = 44
    
    var body: some View {
        ZStack {
            if let appIcon = NSApp.applicationIconImage {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.2),
                    Color.pink.opacity(0.15),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "sparkle")
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .purple.opacity(0.8)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .purple.opacity(0.5), radius: 2)
                        .offset(x: -2, y: 2)
                }
                Spacer()
                HStack {
                    Image(systemName: "sparkle")
                        .font(.system(size: size * 0.15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .shadow(color: .pink.opacity(0.5), radius: 2)
                        .offset(x: 4, y: -4)
                    Spacer()
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.227, style: .continuous))
    }
}

// MARK: - Legacy Cards (kept for compatibility)

struct AIBackgroundRemovalSettingsRow: View {
    @ObservedObject private var manager = AIInstallManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                CachedAsyncImage(url: URL(string: "https://getdroppy.app/assets/icons/ai-bg.jpg")) { image in
                    image.droppyExtensionIcon(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "brain.head.profile").font(.system(size: 24)).foregroundStyle(.blue)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous))
                
                Spacer()
                
                Text("AI")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(AdaptiveColors.overlayAuto(0.1)))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Background Removal")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("Remove backgrounds from images using AI. Works offline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer(minLength: 8)
            
            if manager.isInstalled {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Installed")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                }
            } else {
                Text("One-click install")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 160)
        .aiExtensionCardStyle()
        .contentShape(Rectangle())
        .onTapGesture {
            ExtensionDetailWindowController.shared.present(
                id: "aiBackgroundRemoval",
                parent: SettingsWindowController.shared.activeSettingsWindow
            ) {
                AIInstallView()
            }
        }
    }
}

@available(*, deprecated, renamed: "AIBackgroundRemovalSettingsRow")
struct BackgroundRemovalSettingsRow: View {
    var body: some View {
        AIBackgroundRemovalSettingsRow()
    }
}

// MARK: - Element Capture Info View Wrapper
// Provides the binding for currentShortcut since the view requires it

struct ElementCaptureInfoViewWrapper: View {
    var installCount: Int?
    
    @State private var currentShortcut: SavedShortcut? = {
        if let data = UserDefaults.standard.data(forKey: "elementCaptureShortcut"),
           let shortcut = try? JSONDecoder().decode(SavedShortcut.self, from: data) {
            return shortcut
        }
        return nil
    }()
    
    var body: some View {
        ElementCaptureInfoView(
            currentShortcut: $currentShortcut,
            installCount: installCount
        )
    }
}
