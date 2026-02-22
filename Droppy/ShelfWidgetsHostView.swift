import SwiftUI
import AppKit

struct ShelfWidgetsHostView: View {
    @Bindable var state: DroppyState

    var targetScreen: NSScreen?
    var notchHeight: CGFloat
    var isExternalWithNotchStyle: Bool
    var useAdaptiveForegroundsForTransparentNotch: Bool
    @Binding var isTodoListExpanded: Bool

    let filesWidget: (_ compact: Bool) -> AnyView
    let mediaWidget: (_ compact: Bool) -> AnyView
    let highAlertWidget: (_ compact: Bool) -> AnyView
    let terminalWidget: (_ compact: Bool) -> AnyView
    let cameraWidget: (_ compact: Bool) -> AnyView
    let tasksCalendarWidget: (_ compact: Bool) -> AnyView
    var onPageChanged: (() -> Void)? = nil

    private var manager = ShelfWidgetsManager.shared

    private var profileType: ShelfLayoutProfileType {
        manager.profileType(for: targetScreen)
    }

    private var profile: ShelfProfileConfiguration {
        manager.profile(for: profileType)
    }

    private var activePage: ShelfPageConfiguration {
        manager.activePage(for: profileType)
    }

    private var metrics: ShelfPageMetrics {
        manager.activePageMetrics(
            for: targetScreen,
            notchHeight: notchHeight,
            isExternalWithNotchStyle: isExternalWithNotchStyle
        )
    }

    private var activePageIndex: Int {
        profile.activePageIndex
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack(alignment: .topLeading) {
                ForEach(metrics.frames) { frame in
                    ShelfWidgetCardContainer(
                        type: frame.type,
                        useAdaptiveForegrounds: useAdaptiveForegroundsForTransparentNotch
                    ) {
                        widgetContent(for: frame)
                    }
                    .frame(width: frame.rect.width, height: frame.rect.height)
                    .position(x: frame.rect.midX, y: frame.rect.midY)
                }
            }
            .frame(width: metrics.width, height: metrics.height, alignment: .topLeading)
            .clipped()

            VStack {
                Spacer(minLength: 0)
                if profile.pages.count > 1 {
                    ShelfPageDotsView(
                        pageCount: profile.pages.count,
                        activeIndex: activePageIndex,
                        onSelect: { index in
                            withAnimation(DroppyAnimation.smoothContent(for: targetScreen)) {
                                manager.setActivePage(index: index, for: profileType)
                            }
                            onPageChanged?()
                        }
                    )
                    .padding(.bottom, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(pageSwipeGesture)
        .onAppear {
            manager.refreshMissingWidgetPromptsIfNeeded(for: profileType)
        }
        .onChange(of: activePage.id) { _, _ in
            manager.refreshMissingWidgetPromptsIfNeeded(for: profileType)
        }
        .alert(item: missingPromptBinding) { prompt in
            let descriptor = ShelfWidgetsRegistry.descriptor(for: prompt.widgetType)
            let reason = ShelfWidgetsRegistry.availability(for: prompt.widgetType).reason ?? "Extension unavailable"
            return Alert(
                title: Text("Widget Unavailable"),
                message: Text("\(descriptor.title) is currently unavailable. \(reason)"),
                primaryButton: .destructive(Text("Remove Widget"), action: {
                    manager.resolveMissingPrompt(prompt, removeWidget: true)
                    onPageChanged?()
                }),
                secondaryButton: .default(Text("Keep Placeholder"), action: {
                    manager.resolveMissingPrompt(prompt, removeWidget: false)
                })
            )
        }
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > 60 else { return }
                withAnimation(DroppyAnimation.smoothContent(for: targetScreen)) {
                    if value.translation.width < 0 {
                        manager.goToNextPage(for: targetScreen)
                    } else {
                        manager.goToPreviousPage(for: targetScreen)
                    }
                }
                onPageChanged?()
            }
    }

    private var missingPromptBinding: Binding<ShelfMissingWidgetPrompt?> {
        Binding(
            get: { manager.nextMissingPrompt(for: profileType) },
            set: { _ in }
        )
    }

    @ViewBuilder
    private func widgetContent(for frame: ShelfWidgetLayoutFrame) -> some View {
        let availability = ShelfWidgetsRegistry.availability(for: frame.type)
        if !availability.isAvailable {
            ShelfUnavailableWidgetCard(
                type: frame.type,
                reason: availability.reason,
                useAdaptiveForegrounds: useAdaptiveForegroundsForTransparentNotch,
                onOpenSettings: {
                    openSettings(for: frame.type)
                }
            )
        } else {
            switch frame.type {
            case .files:
                filesWidget(frame.compactMode)
            case .media:
                mediaWidget(frame.compactMode)
            case .highAlert:
                highAlertWidget(frame.compactMode)
            case .terminal:
                terminalWidget(frame.compactMode)
            case .camera:
                cameraWidget(frame.compactMode)
            case .tasksCalendar:
                tasksCalendarWidget(frame.compactMode)
            }
        }
    }

    private func openSettings(for type: ShelfWidgetType) {
        switch type {
        case .files:
            SettingsWindowController.shared.showSettings(tab: .shelf)
        case .media:
            SettingsWindowController.shared.showSettings(tab: .huds)
        case .highAlert:
            SettingsWindowController.shared.showSettings(openingExtension: .caffeine)
        case .terminal:
            SettingsWindowController.shared.showSettings(openingExtension: .terminalNotch)
        case .camera:
            SettingsWindowController.shared.showSettings(openingExtension: .camera)
        case .tasksCalendar:
            SettingsWindowController.shared.showSettings(openingExtension: .todo)
        }
    }
}

struct ShelfWidgetCardContainer<Content: View>: View {
    let type: ShelfWidgetType
    let useAdaptiveForegrounds: Bool
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    useAdaptiveForegrounds
                        ? AdaptiveColors.overlayAuto(0.12)
                        : Color.black.opacity(0.34)
                )
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    useAdaptiveForegrounds
                        ? AdaptiveColors.overlayAuto(0.12)
                        : Color.white.opacity(0.08),
                    lineWidth: 1
                )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ShelfUnavailableWidgetCard: View {
    let type: ShelfWidgetType
    let reason: String?
    let useAdaptiveForegrounds: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        let descriptor = ShelfWidgetsRegistry.descriptor(for: type)
        VStack(alignment: .leading, spacing: 8) {
            Label(descriptor.title, systemImage: descriptor.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(useAdaptiveForegrounds ? AdaptiveColors.primaryTextAuto : .white)

            Text(reason ?? "Unavailable")
                .font(.system(size: 11))
                .foregroundStyle(useAdaptiveForegrounds ? AdaptiveColors.secondaryTextAuto : .white.opacity(0.72))
                .lineLimit(3)

            Spacer(minLength: 0)

            Button("Open Settings") {
                onOpenSettings()
            }
            .buttonStyle(DroppyPillButtonStyle(size: .small))
            .disabled(reason == nil)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ShelfPageDotsView: View {
    let pageCount: Int
    let activeIndex: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Button {
                    onSelect(index)
                } label: {
                    Circle()
                        .fill(index == activeIndex ? Color.white.opacity(0.95) : Color.white.opacity(0.35))
                        .frame(width: index == activeIndex ? 8 : 6, height: index == activeIndex ? 8 : 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.35))
        )
    }
}
