//
//  ExtensionInfoView.swift
//  Droppy
//
//  Extension information popups matching AIInstallView styling
//

import SwiftUI
import AppKit

// MARK: - Extension Info View

struct ExtensionInfoView: View {
    let extensionType: ExtensionType
    var onAction: (() -> Void)?
    var installCount: Int?
    @AppStorage(AppPreferenceKey.disableAnalytics) private var disableAnalytics = PreferenceDefault.disableAnalytics
    @Environment(\.dismiss) private var dismiss
    @Environment(\.droppyPanelCloseAction) private var panelCloseAction
    @State private var isHoveringAction = false
    @State private var isHoveringClose = false

    private var isInstalled: Bool {
        extensionType.isInstalledInSystem
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header (fixed)
            headerSection
            
            Divider()
                .padding(.horizontal, 24)
            
            // Scrollable content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    // Features section
                    featuresSection
                    
                    // Screenshot section
                    screenshotSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .frame(maxHeight: 500)
            
            Divider()
                .padding(.horizontal, 24)
            
            // Buttons (fixed)
            buttonSection
        }
        .frame(width: 450)
        .fixedSize(horizontal: true, vertical: true)
        .droppyLiquidPopoverSurface(cornerRadius: DroppyRadius.xl)
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.xl, style: .continuous))
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon
            extensionType.iconView
                .shadow(color: extensionType.categoryColor.opacity(0.3), radius: 8, y: 4)
            
            // Title
            Text(extensionType.title)
                .font(.title2.bold())
                .foregroundStyle(.primary)
            
            // Stats row: installs + category badge
            HStack(spacing: 12) {
                if !disableAnalytics {
                    // Installs
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                        Text(AnalyticsService.shared.isDisabled ? "–" : "\(installCount ?? 0)")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundStyle(.secondary)

                }
                
                if disableAnalytics {
                    Text("Analytics off")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.tertiary)
                }
                
                // Category badge
                Text(extensionType.category)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(extensionType.categoryColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(extensionType.categoryColor.opacity(0.15))
                    )

                Text(isInstalled ? "Installed" : "Needs Setup")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isInstalled ? .green : .orange)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill((isInstalled ? Color.green : Color.orange).opacity(0.15))
                    )
            }
            
            if disableAnalytics {
                Text("Install/download stats are hidden.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            // Subtitle
            Text(extensionType.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
    
    // MARK: - Screenshot Section (Left)
    
    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Screenshot preview loaded from web (cached to prevent flashing)
            if let screenshotURL = extensionType.screenshotURL {
                CachedAsyncImage(url: screenshotURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                                .strokeBorder(AdaptiveColors.subtleBorderAuto, lineWidth: 1)
                        )
                } placeholder: {
                    EmptyView()
                }
            }
        }
    }
    
    // MARK: - Features Section (Right)
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(extensionType.description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            ForEach(Array(extensionType.features.enumerated()), id: \.offset) { _, feature in
                featureRow(icon: feature.icon, text: feature.text)
            }
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(extensionType.categoryColor)
                .frame(width: 24)
            
            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }
    
    // MARK: - Buttons
    
    private var buttonSection: some View {
        HStack(spacing: 8) {
            // Close button
            Button {
                closePanelOrDismiss(panelCloseAction, dismiss: dismiss)
            } label: {
                Text("Close")
            }
            .buttonStyle(DroppyPillButtonStyle(size: .small))
            
            Spacer()
            
            // Action button (optional)
            if let action = onAction {
                Button {
                    AnalyticsService.shared.trackExtensionActivation(extensionId: extensionType.rawValue)
                    action()
                } label: {
                    Text(primaryActionText)
                }
                .buttonStyle(DroppyAccentButtonStyle(color: extensionType.categoryColor, size: .small))
            }
            
            // Disable button
            DisableExtensionButton(extensionType: extensionType)
        }
        .padding(DroppySpacing.lg)
    }
    
    private var primaryActionText: String {
        if !isInstalled {
            switch extensionType {
            case .spotify, .appleMusic:
                return "Set Up"
            case .finder, .finderServices, .windowSnap, .voiceTranscribe, .elementCapture, .terminalNotch, .camera, .notificationHUD, .caffeine, .menuBarManager, .pomodoro, .todo, .teleprompty:
                return "Set Up"
            case .quickshare:
                return "Enable"
            case .aiBackgroundRemoval, .ffmpegVideoCompression, .alfred:
                return "Install"
            }
        }
        
        switch extensionType {
        case .aiBackgroundRemoval: return "Manage"
        case .alfred: return "Reinstall"
        case .finder, .finderServices: return "Open Settings"
        case .spotify: return "Open Spotify"
        case .appleMusic: return "Open Music"
        case .elementCapture: return "Configure"
        case .windowSnap: return "Configure"
        case .voiceTranscribe: return "Configure"
        case .ffmpegVideoCompression: return "Manage"
        case .terminalNotch: return "Configure"
        case .camera: return "Configure"
        case .quickshare: return "Manage"
        case .notificationHUD: return "Configure"
        case .caffeine: return "Configure"
        case .menuBarManager: return "Configure"
        case .pomodoro: return "Configure"
        case .todo: return "Configure"
        case .teleprompty: return "Configure"
        }
    }

    private var actionText: String {
        switch extensionType {
        case .aiBackgroundRemoval: return "Install"
        case .alfred: return "Install Workflow"
        case .finder, .finderServices: return "Configure"
        case .spotify: return "Connect"
        case .appleMusic: return "Connect"
        case .elementCapture: return "Configure Shortcut"
        case .windowSnap: return "Configure Shortcuts"
        case .voiceTranscribe: return "Configure"
        case .ffmpegVideoCompression: return "Install FFmpeg"
        case .terminalNotch: return "Configure"
        case .camera: return "Configure"
        case .quickshare: return "Manage Uploads"
        case .notificationHUD: return "Configure"
        case .caffeine: return "Configure"
        case .menuBarManager: return "Configure"
        case .pomodoro: return "Configure"
        case .todo: return "Configure"
        case .teleprompty: return "Configure"
        }
    }

    private var actionIcon: String {
        switch extensionType {
        case .aiBackgroundRemoval: return "arrow.down.circle.fill"
        case .alfred: return "arrow.down.circle.fill"
        case .finder, .finderServices: return "gearshape"
        case .spotify: return "link"
        case .appleMusic: return "link"
        case .elementCapture: return "keyboard"
        case .windowSnap: return "keyboard"
        case .voiceTranscribe: return "mic.fill"
        case .ffmpegVideoCompression: return "arrow.down.circle.fill"
        case .terminalNotch: return "terminal"
        case .camera: return "camera.fill"
        case .quickshare: return "tray.full"
        case .notificationHUD: return "bell.badge"
        case .caffeine: return "cup.and.saucer.fill"
        case .menuBarManager: return "menubar.rectangle"
        case .pomodoro: return "timer"
        case .todo: return "checklist"
        case .teleprompty: return "text.bubble"
        }
    }
}

// MARK: - Preview

#Preview {
    ExtensionInfoView(extensionType: .alfred) {
        print("Action")
    }
}
