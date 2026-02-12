import SwiftUI
import AppKit

// MARK: - Onboarding Flow Model

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome = 0
    case core
    case workflow
    case appearance
    case signals
    case ready

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .core: return "Core Setup"
        case .workflow: return "How It Works"
        case .appearance: return "Personalize"
        case .signals: return "Media and HUDs"
        case .ready: return "Launch"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome: return "What Droppy is and why it feels native"
        case .core: return "Pick your core tools in one pass"
        case .workflow: return "Understand the interaction model quickly"
        case .appearance: return "Shape the look and behavior to your Mac"
        case .signals: return "Choose the overlays you want to see"
        case .ready: return "Final check and privacy preferences"
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "sparkles"
        case .core: return "square.stack.3d.up"
        case .workflow: return "arrow.triangle.branch"
        case .appearance: return "paintbrush"
        case .signals: return "waveform.path"
        case .ready: return "checkmark.seal"
        }
    }

    var accent: Color {
        switch self {
        case .welcome: return Color(red: 0.20, green: 0.55, blue: 0.97)
        case .core: return Color(red: 0.12, green: 0.66, blue: 0.78)
        case .workflow: return Color(red: 0.14, green: 0.59, blue: 0.52)
        case .appearance: return Color(red: 0.92, green: 0.56, blue: 0.21)
        case .signals: return Color(red: 0.18, green: 0.53, blue: 0.94)
        case .ready: return Color(red: 0.18, green: 0.67, blue: 0.39)
        }
    }
}

// MARK: - Main Onboarding View

struct OnboardingView: View {
    static let preferredWindowSize = CGSize(width: 920, height: 640)

    // Core features
    @AppStorage(AppPreferenceKey.enableNotchShelf) private var enableShelf = PreferenceDefault.enableNotchShelf
    @AppStorage(AppPreferenceKey.enableFloatingBasket) private var enableBasket = PreferenceDefault.enableFloatingBasket
    @AppStorage(AppPreferenceKey.instantBasketOnDrag) private var instantBasketOnDrag = PreferenceDefault.instantBasketOnDrag
    @AppStorage(AppPreferenceKey.enableAutoClean) private var enableAutoClean = PreferenceDefault.enableAutoClean
    @AppStorage(AppPreferenceKey.enableClipboard) private var enableClipboard = PreferenceDefault.enableClipboard

    // Media and HUDs
    @AppStorage(AppPreferenceKey.showMediaPlayer) private var showMediaPlayer = PreferenceDefault.showMediaPlayer
    @AppStorage(AppPreferenceKey.enableHUDReplacement) private var enableHUD = PreferenceDefault.enableHUDReplacement
    @AppStorage(AppPreferenceKey.enableBatteryHUD) private var enableBatteryHUD = PreferenceDefault.enableBatteryHUD
    @AppStorage(AppPreferenceKey.enableCapsLockHUD) private var enableCapsLockHUD = PreferenceDefault.enableCapsLockHUD
    @AppStorage(AppPreferenceKey.enableAirPodsHUD) private var enableAirPodsHUD = PreferenceDefault.enableAirPodsHUD
    @AppStorage(AppPreferenceKey.enableDNDHUD) private var enableDNDHUD = PreferenceDefault.enableDNDHUD
    @AppStorage(AppPreferenceKey.enableUpdateHUD) private var enableUpdateHUD = PreferenceDefault.enableUpdateHUD

    // Appearance and feel
    @AppStorage(AppPreferenceKey.useDynamicIslandStyle) private var useDynamicIslandStyle = PreferenceDefault.useDynamicIslandStyle
    @AppStorage(AppPreferenceKey.externalDisplayUseDynamicIsland) private var externalDisplayUseDynamicIsland = PreferenceDefault.externalDisplayUseDynamicIsland
    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground
    @AppStorage(AppPreferenceKey.enableParallaxEffect) private var enableParallaxEffect = PreferenceDefault.enableParallaxEffect
    @AppStorage(AppPreferenceKey.autoHideOnFullscreen) private var autoHideOnFullscreen = PreferenceDefault.autoHideOnFullscreen
    @AppStorage(AppPreferenceKey.enableHapticFeedback) private var enableHapticFeedback = PreferenceDefault.enableHapticFeedback

    // System and privacy
    @AppStorage(AppPreferenceKey.disableAnalytics) private var disableAnalytics = PreferenceDefault.disableAnalytics
    @AppStorage(AppPreferenceKey.startAtLogin) private var startAtLogin = PreferenceDefault.startAtLogin

    @State private var currentPage: OnboardingPage = .welcome
    @State private var direction: Int = 1
    @State private var showConfetti = false
    @State private var hasPlayedLaunchConfetti = false

    let onComplete: () -> Void

    private var pageIndex: Int {
        currentPage.rawValue
    }

    private var progress: Double {
        let total = Double(max(OnboardingPage.allCases.count - 1, 1))
        return Double(pageIndex) / total
    }

    private var hasBuiltInNotch: Bool {
        NSScreen.builtInWithNotch != nil
    }

    private var isOnExternalDisplay: Bool {
        guard let mainScreen = NSScreen.main else { return false }
        return !mainScreen.isBuiltIn
    }

    private var styleBinding: Binding<Bool> {
        if hasBuiltInNotch && isOnExternalDisplay {
            return $externalDisplayUseDynamicIsland
        }
        return $useDynamicIslandStyle
    }

    private var canEditCurrentDisplayStyle: Bool {
        !hasBuiltInNotch || isOnExternalDisplay
    }

    private var styleSectionTitle: String {
        if hasBuiltInNotch && isOnExternalDisplay {
            return "External display shape"
        }
        if hasBuiltInNotch {
            return "Built-in notch shape"
        }
        return "Droppy shape"
    }

    private var styleSectionSubtitle: String {
        if hasBuiltInNotch && isOnExternalDisplay {
            return "Choose how Droppy should render on your external monitor."
        }
        if hasBuiltInNotch {
            return "Your MacBook has a physical notch, so this display uses notch mode."
        }
        return "Choose between Notch and Island style for this display."
    }

    private var activeHighlights: [String] {
        var values: [String] = []
        if enableShelf { values.append("Shelf") }
        if enableBasket { values.append("Basket") }
        if enableClipboard { values.append("Clipboard") }
        if showMediaPlayer { values.append("Now Playing") }
        if enableHUD { values.append("Volume and Brightness HUD") }
        if styleBinding.wrappedValue { values.append("Island Style") }
        if startAtLogin { values.append("Start at Login") }
        return values
    }

    var body: some View {
        ZStack {
            OnboardingBackdrop(accent: currentPage.accent)

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 14)

                Divider()
                    .overlay(AdaptiveColors.overlayAuto(0.08))

                HStack(spacing: 0) {
                    sidebar
                        .frame(width: 250)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 20)

                    Divider()
                        .overlay(AdaptiveColors.overlayAuto(0.08))

                    pageContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                }

                Divider()
                    .overlay(AdaptiveColors.overlayAuto(0.08))

                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
        }
        .frame(width: Self.preferredWindowSize.width, height: Self.preferredWindowSize.height)
        .background(windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DroppyRadius.xxl, style: .continuous)
                .strokeBorder(AdaptiveColors.overlayAuto(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 18)
        .overlay {
            if showConfetti {
                OnboardingConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: currentPage) { _, newValue in
            if newValue == .ready {
                playLaunchCelebrationIfNeeded()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(currentPage.accent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: currentPage.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(currentPage.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Droppy Onboarding")
                        .font(.system(size: 14, weight: .semibold))
                    Text(currentPage.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 18)

            VStack(alignment: .trailing, spacing: 7) {
                Text("Step \(pageIndex + 1) of \(OnboardingPage.allCases.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AdaptiveColors.overlayAuto(0.10))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [currentPage.accent.opacity(0.75), currentPage.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(16, geo.size.width * progress))
                    }
                }
                .frame(width: 190, height: 7)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Setup Path")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(OnboardingPage.allCases) { page in
                    OnboardingStepRow(
                        page: page,
                        isCurrent: page == currentPage,
                        isCompleted: page.rawValue < currentPage.rawValue,
                        action: {
                            direction = page.rawValue >= currentPage.rawValue ? 1 : -1
                            withAnimation(DroppyAnimation.viewTransition) {
                                currentPage = page
                            }
                        }
                    )
                }
            }

            Spacer(minLength: 8)

            PremiumCard(accent: currentPage.accent, emphasis: false) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quality baseline")
                        .font(.system(size: 12, weight: .semibold))

                    Text("This setup configures Droppy for smooth defaults now, without locking you in.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text("About one minute")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var pageContent: some View {
        ZStack {
            ForEach(OnboardingPage.allCases) { page in
                if page == currentPage {
                    content(for: page)
                        .transition(pageTransition)
                }
            }
        }
        .animation(DroppyAnimation.viewTransition, value: currentPage)
    }

    private var footer: some View {
        HStack {
            Button(action: goBack) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Back")
                }
            }
            .buttonStyle(DroppyPillButtonStyle(size: .small))
            .opacity(currentPage == .welcome ? 0 : 1)
            .disabled(currentPage == .welcome)

            Spacer(minLength: 14)

            HStack(spacing: 6) {
                ForEach(OnboardingPage.allCases) { page in
                    Circle()
                        .fill(page == currentPage ? currentPage.accent : AdaptiveColors.overlayAuto(0.24))
                        .frame(width: page == currentPage ? 9 : 6, height: page == currentPage ? 9 : 6)
                        .animation(DroppyAnimation.hoverQuick, value: currentPage)
                }
            }

            Spacer(minLength: 14)

            Button(action: goNext) {
                HStack(spacing: 6) {
                    Text(currentPage == .ready ? "Start Droppy" : "Continue")
                    Image(systemName: currentPage == .ready ? "arrow.right" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(DroppyAccentButtonStyle(color: currentPage == .ready ? .green : currentPage.accent, size: .small))
        }
    }

    private var windowBackground: some View {
        Group {
            if useTransparentBackground {
                Rectangle().fill(.ultraThinMaterial)
            } else {
                AdaptiveColors.panelBackgroundAuto
            }
        }
    }

    private var pageTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: direction > 0 ? 28 : -28, y: 0)),
            removal: .opacity.combined(with: .offset(x: direction > 0 ? -28 : 28, y: 0))
        )
    }

    private func goNext() {
        if currentPage == .ready {
            onComplete()
            return
        }

        direction = 1
        withAnimation(DroppyAnimation.viewTransition) {
            currentPage = OnboardingPage(rawValue: currentPage.rawValue + 1) ?? .ready
        }
    }

    private func goBack() {
        guard currentPage != .welcome else { return }
        direction = -1
        withAnimation(DroppyAnimation.viewTransition) {
            currentPage = OnboardingPage(rawValue: currentPage.rawValue - 1) ?? .welcome
        }
    }

    private func playLaunchCelebrationIfNeeded() {
        guard !hasPlayedLaunchConfetti else { return }
        hasPlayedLaunchConfetti = true
        showConfetti = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            showConfetti = false
        }
    }

    @ViewBuilder
    private func content(for page: OnboardingPage) -> some View {
        switch page {
        case .welcome:
            WelcomePage(hasBuiltInNotch: hasBuiltInNotch)

        case .core:
            CoreSetupPage(
                enableShelf: $enableShelf,
                enableAutoClean: $enableAutoClean,
                enableBasket: $enableBasket,
                instantBasketOnDrag: $instantBasketOnDrag,
                enableClipboard: $enableClipboard
            )

        case .workflow:
            WorkflowPage(instantBasketOnDrag: instantBasketOnDrag)

        case .appearance:
            AppearancePage(
                styleBinding: styleBinding,
                canEditCurrentDisplayStyle: canEditCurrentDisplayStyle,
                styleSectionTitle: styleSectionTitle,
                styleSectionSubtitle: styleSectionSubtitle,
                useTransparentBackground: $useTransparentBackground,
                enableParallaxEffect: $enableParallaxEffect,
                autoHideOnFullscreen: $autoHideOnFullscreen,
                enableHapticFeedback: $enableHapticFeedback
            )

        case .signals:
            SignalsPage(
                showMediaPlayer: $showMediaPlayer,
                enableHUD: $enableHUD,
                enableBatteryHUD: $enableBatteryHUD,
                enableCapsLockHUD: $enableCapsLockHUD,
                enableAirPodsHUD: $enableAirPodsHUD,
                enableDNDHUD: $enableDNDHUD,
                enableUpdateHUD: $enableUpdateHUD
            )

        case .ready:
            ReadyPage(
                activeHighlights: activeHighlights,
                disableAnalytics: $disableAnalytics,
                startAtLogin: $startAtLogin
            )
        }
    }
}

// MARK: - Pages

private struct WelcomePage: View {
    let hasBuiltInNotch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PremiumCard(accent: Color(red: 0.20, green: 0.55, blue: 0.97), emphasis: true) {
                HStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.14))
                            .frame(width: 96, height: 96)
                        NotchFace(size: 70, isExcited: true)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Droppy, done right")
                            .font(.system(size: 28, weight: .bold, design: .rounded))

                        Text("A native layer on top of macOS for faster drag-and-drop, clipboard recall, and contextual HUDs.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            TinyBadge(icon: "bolt.fill", text: "Fast")
                            TinyBadge(icon: "sparkles", text: "Polished")
                            TinyBadge(icon: "lock.shield", text: "Private by default")
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                ValueCard(
                    icon: "tray.and.arrow.down.fill",
                    title: "Shelf",
                    detail: "Temporary shelf at the notch for files, folders, and quick re-drop.",
                    accent: Color(red: 0.15, green: 0.62, blue: 0.97)
                )

                ValueCard(
                    icon: "basket.fill",
                    title: "Basket",
                    detail: "Floating drop target for cross-display workflows and precision drops.",
                    accent: Color(red: 0.14, green: 0.59, blue: 0.52)
                )

                ValueCard(
                    icon: "doc.on.clipboard.fill",
                    title: "Clipboard",
                    detail: "Searchable history with OCR and favorites when memory fails.",
                    accent: Color(red: 0.14, green: 0.66, blue: 0.78)
                )
            }

            PremiumCard(accent: Color(red: 0.92, green: 0.56, blue: 0.21), emphasis: false) {
                HStack(spacing: 14) {
                    Image(systemName: hasBuiltInNotch ? "laptopcomputer" : "display")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Color(red: 0.92, green: 0.56, blue: 0.21))
                        .frame(width: 28)

                    Text(
                        hasBuiltInNotch
                        ? "Your Mac has a physical notch. Droppy will keep interactions aligned to hardware behavior."
                        : "No hardware notch detected. Droppy can render in Notch or Island style."
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct CoreSetupPage: View {
    @Binding var enableShelf: Bool
    @Binding var enableAutoClean: Bool
    @Binding var enableBasket: Bool
    @Binding var instantBasketOnDrag: Bool
    @Binding var enableClipboard: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose your core workflow")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("These are the three features most users touch every day. Start focused; refine later in Settings.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            ToggleFeatureCard(
                icon: "tray.and.arrow.down.fill",
                title: "Enable Notch Shelf",
                subtitle: "Drag into the notch area to park items temporarily.",
                accent: Color(red: 0.15, green: 0.62, blue: 0.97),
                isOn: $enableShelf
            ) {
                if enableShelf {
                    InlineToggleRow(
                        icon: "trash.fill",
                        label: "Auto-clean after dragging items out",
                        accent: .gray,
                        isOn: $enableAutoClean
                    )
                }
            }

            ToggleFeatureCard(
                icon: "basket.fill",
                title: "Enable Floating Basket",
                subtitle: "Use a movable drop zone when your cursor is away from the notch.",
                accent: Color(red: 0.14, green: 0.59, blue: 0.52),
                isOn: $enableBasket
            ) {
                if enableBasket {
                    InlineToggleRow(
                        icon: "bolt.fill",
                        label: "Show instantly when drag starts",
                        accent: Color(red: 0.92, green: 0.56, blue: 0.21),
                        isOn: $instantBasketOnDrag
                    )
                }
            }

            ToggleFeatureCard(
                icon: "doc.on.clipboard.fill",
                title: "Enable Clipboard Manager",
                subtitle: "Keep searchable history and recover copied text, links, and snippets.",
                accent: Color(red: 0.14, green: 0.66, blue: 0.78),
                isOn: $enableClipboard
            ) {
                HStack(spacing: 8) {
                    TinyBadge(icon: "command", text: "Cmd")
                    Text("+")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TinyBadge(icon: "shift", text: "Shift")
                    Text("+")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TinyBadge(icon: "keyboard", text: "Space")
                    Spacer(minLength: 0)
                    Text("Open Clipboard")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct WorkflowPage: View {
    let instantBasketOnDrag: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How Droppy works")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Think of Droppy as a lightweight interaction layer above the menu bar.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            PremiumCard(accent: Color(red: 0.14, green: 0.59, blue: 0.52), emphasis: true) {
                VStack(spacing: 12) {
                    WorkflowLine(
                        step: "1",
                        icon: "arrow.up.and.down.and.arrow.left.and.right",
                        title: "Drag starts",
                        detail: "Droppy watches the drag context without replacing Finder behavior.",
                        accent: Color(red: 0.15, green: 0.62, blue: 0.97)
                    )

                    WorkflowLine(
                        step: "2",
                        icon: "tray.full.fill",
                        title: "Choose target",
                        detail: instantBasketOnDrag
                            ? "Shelf or Basket appears instantly, depending on your preference."
                            : "Shelf stays primary; shake to summon Basket when needed.",
                        accent: Color(red: 0.14, green: 0.59, blue: 0.52)
                    )

                    WorkflowLine(
                        step: "3",
                        icon: "arrowshape.turn.up.right.fill",
                        title: "Drop and continue",
                        detail: "Items can be re-dragged to apps, folders, mail, or messages with minimal friction.",
                        accent: Color(red: 0.14, green: 0.66, blue: 0.78)
                    )
                }
            }

            HStack(spacing: 12) {
                PremiumCard(accent: Color(red: 0.20, green: 0.55, blue: 0.97), emphasis: false) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Design principle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Droppy should feel like part of macOS, not another utility overlay.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                PremiumCard(accent: Color(red: 0.92, green: 0.56, blue: 0.21), emphasis: false) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Confidence")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Most settings below are reversible instantly in Droppy Settings.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AppearancePage: View {
    @Binding var styleBinding: Bool
    let canEditCurrentDisplayStyle: Bool
    let styleSectionTitle: String
    let styleSectionSubtitle: String

    @Binding var useTransparentBackground: Bool
    @Binding var enableParallaxEffect: Bool
    @Binding var autoHideOnFullscreen: Bool
    @Binding var enableHapticFeedback: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Personalize the experience")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Tune visuals and feel without overloading setup.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            PremiumCard(accent: Color(red: 0.92, green: 0.56, blue: 0.21), emphasis: true) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(styleSectionTitle)
                        .font(.system(size: 13, weight: .semibold))

                    Text(styleSectionSubtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        StyleCard(
                            title: "Notch",
                            subtitle: "Hardware-inspired",
                            accent: Color(red: 0.20, green: 0.55, blue: 0.97),
                            isSelected: !styleBinding,
                            enabled: canEditCurrentDisplayStyle,
                            action: { styleBinding = false }
                        ) {
                            NotchGlyph()
                                .fill(Color(red: 0.20, green: 0.55, blue: 0.97))
                                .frame(width: 60, height: 20)
                        }

                        StyleCard(
                            title: "Island",
                            subtitle: "Softer capsule",
                            accent: Color(red: 0.14, green: 0.59, blue: 0.52),
                            isSelected: styleBinding,
                            enabled: canEditCurrentDisplayStyle,
                            action: { styleBinding = true }
                        ) {
                            Capsule()
                                .fill(Color(red: 0.14, green: 0.59, blue: 0.52))
                                .frame(width: 60, height: 16)
                        }
                    }

                    if !canEditCurrentDisplayStyle {
                        Text("Style selection is locked on this display because your built-in notch is physical.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            PremiumCard(accent: Color(red: 0.20, green: 0.55, blue: 0.97), emphasis: false) {
                VStack(spacing: 8) {
                    InlineToggleRow(
                        icon: "drop.fill",
                        label: "Transparent panel background",
                        accent: Color(red: 0.20, green: 0.55, blue: 0.97),
                        isOn: $useTransparentBackground
                    )

                    InlineToggleRow(
                        icon: "sparkles",
                        label: "Parallax motion for depth",
                        accent: Color(red: 0.14, green: 0.66, blue: 0.78),
                        isOn: $enableParallaxEffect
                    )

                    InlineToggleRow(
                        icon: "arrow.down.right.and.arrow.up.left",
                        label: "Auto-hide in fullscreen apps",
                        accent: Color(red: 0.92, green: 0.56, blue: 0.21),
                        isOn: $autoHideOnFullscreen
                    )

                    InlineToggleRow(
                        icon: "hand.tap.fill",
                        label: "Trackpad haptic feedback",
                        accent: Color(red: 0.14, green: 0.59, blue: 0.52),
                        isOn: $enableHapticFeedback
                    )
                }
            }

            Spacer(minLength: 0)
        }
    }
}

private struct SignalsPage: View {
    @Binding var showMediaPlayer: Bool
    @Binding var enableHUD: Bool
    @Binding var enableBatteryHUD: Bool
    @Binding var enableCapsLockHUD: Bool
    @Binding var enableAirPodsHUD: Bool
    @Binding var enableDNDHUD: Bool
    @Binding var enableUpdateHUD: Bool

    private var mediaAvailable: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Media and HUD signals")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("Select what Droppy should surface in the notch area.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                PremiumCard(accent: Color(red: 0.14, green: 0.59, blue: 0.52), emphasis: true) {
                    VStack(spacing: 8) {
                        InlineToggleRow(
                            icon: "music.note",
                            label: "Now Playing",
                            accent: Color(red: 0.14, green: 0.59, blue: 0.52),
                            isOn: $showMediaPlayer,
                            enabled: mediaAvailable
                        )

                        if !mediaAvailable {
                            Text("Now Playing requires macOS 15 or later.")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        InlineToggleRow(
                            icon: "speaker.wave.2.fill",
                            label: "Volume and Brightness HUD",
                            accent: Color(red: 0.20, green: 0.55, blue: 0.97),
                            isOn: $enableHUD
                        )
                    }
                }

                PremiumCard(accent: Color(red: 0.20, green: 0.55, blue: 0.97), emphasis: false) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8),
                            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 8)
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        CompactSignalToggle(icon: "battery.100percent.bolt", title: "Battery", isOn: $enableBatteryHUD)
                        CompactSignalToggle(icon: "capslock.fill", title: "Caps Lock", isOn: $enableCapsLockHUD)
                        CompactSignalToggle(icon: "airpodspro", title: "AirPods", isOn: $enableAirPodsHUD)
                        CompactSignalToggle(icon: "moon.fill", title: "Focus", isOn: $enableDNDHUD)
                        CompactSignalToggle(icon: "arrow.down.circle.fill", title: "Updates", isOn: $enableUpdateHUD)
                    }
                }
            }

            PremiumCard(accent: Color(red: 0.14, green: 0.66, blue: 0.78), emphasis: false) {
                Text("Tip: Keep only the HUDs you care about enabled. A curated set feels quieter and more premium.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ReadyPage: View {
    let activeHighlights: [String]
    @Binding var disableAnalytics: Bool
    @Binding var startAtLogin: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ready to launch")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Text("You can tweak everything later in Settings, but this gets Droppy into a strong first-run state.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            PremiumCard(accent: Color(red: 0.18, green: 0.67, blue: 0.39), emphasis: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 0.18, green: 0.67, blue: 0.39))
                        Text("Current selection")
                            .font(.system(size: 13, weight: .semibold))
                    }

                    if activeHighlights.isEmpty {
                        Text("No modules selected yet. Continue anyway and configure later.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        FlexibleBadgeWrap(items: activeHighlights)
                    }
                }
            }

            PremiumCard(accent: Color(red: 0.20, green: 0.55, blue: 0.97), emphasis: false) {
                VStack(spacing: 8) {
                    InlineToggleRow(
                        icon: "power",
                        label: "Start Droppy at login",
                        accent: Color(red: 0.20, green: 0.55, blue: 0.97),
                        isOn: $startAtLogin
                    )

                    InlineToggleRow(
                        icon: "hand.raised.fill",
                        label: "Disable analytics",
                        accent: Color(red: 0.92, green: 0.56, blue: 0.21),
                        isOn: $disableAnalytics
                    )
                }
            }

            PremiumCard(accent: Color(red: 0.14, green: 0.59, blue: 0.52), emphasis: false) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick start")
                        .font(.system(size: 12, weight: .semibold))

                    QuickGuideLine(action: "Drag file to notch", result: "Store on Shelf")
                    QuickGuideLine(action: "Shake while dragging", result: "Reveal Basket")
                    QuickGuideLine(action: "Cmd+Shift+Space", result: "Open Clipboard")
                    QuickGuideLine(action: "Right-click notch", result: "Open Settings")
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Supporting Components

private struct OnboardingBackdrop: View {
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    AdaptiveColors.overlayAuto(0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(accent.opacity(0.13))
                .frame(width: 340, height: 340)
                .blur(radius: 70)
                .offset(x: 220, y: -220)

            Circle()
                .fill(Color(red: 0.12, green: 0.66, blue: 0.78).opacity(0.08))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: -250, y: 220)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AdaptiveColors.overlayAuto(0.05), lineWidth: 1)
                .padding(1)
        }
        .ignoresSafeArea()
    }
}

private struct OnboardingStepRow: View {
    let page: OnboardingPage
    let isCurrent: Bool
    let isCompleted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous)
                        .fill(isCurrent ? page.accent.opacity(0.16) : AdaptiveColors.overlayAuto(0.07))
                        .frame(width: 32, height: 32)

                    if isCompleted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(page.accent)
                    } else {
                        Image(systemName: page.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isCurrent ? page.accent : .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(page.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(page.subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                    .fill(isCurrent ? page.accent.opacity(0.10) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                    .stroke(isCurrent ? page.accent.opacity(0.34) : AdaptiveColors.overlayAuto(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PremiumCard<Content: View>: View {
    let accent: Color
    let emphasis: Bool
    let content: Content

    init(accent: Color, emphasis: Bool, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.emphasis = emphasis
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                accent.opacity(emphasis ? 0.14 : 0.08),
                                AdaptiveColors.overlayAuto(0.03)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous)
                    .stroke(accent.opacity(emphasis ? 0.32 : 0.18), lineWidth: 1)
            )
    }
}

private struct ValueCard: View {
    let icon: String
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        PremiumCard(accent: accent, emphasis: false) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }

                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ToggleFeatureCard<Detail: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    @Binding var isOn: Bool
    let detail: Detail

    init(
        icon: String,
        title: String,
        subtitle: String,
        accent: Color,
        isOn: Binding<Bool>,
        @ViewBuilder detail: () -> Detail
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        _isOn = isOn
        self.detail = detail()
    }

    var body: some View {
        PremiumCard(accent: accent, emphasis: isOn) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous)
                            .fill(accent.opacity(0.20))
                            .frame(width: 34, height: 34)

                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Toggle("", isOn: $isOn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                detail
                    .opacity(isOn ? 1 : 0.7)
            }
        }
    }
}

private struct InlineToggleRow: View {
    let icon: String
    let label: String
    let accent: Color
    @Binding var isOn: Bool
    var enabled: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 18)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(!enabled)
        }
        .opacity(enabled ? 1 : 0.55)
    }
}

private struct WorkflowLine: View {
    let step: String
    let icon: String
    let title: String
    let detail: String
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 34, height: 34)

                Text(step)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct StyleCard<Preview: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    let isSelected: Bool
    let enabled: Bool
    let action: () -> Void
    let preview: Preview

    init(
        title: String,
        subtitle: String,
        accent: Color,
        isSelected: Bool,
        enabled: Bool,
        action: @escaping () -> Void,
        @ViewBuilder preview: () -> Preview
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.isSelected = isSelected
        self.enabled = enabled
        self.action = action
        self.preview = preview()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                        .fill(isSelected ? accent.opacity(0.18) : AdaptiveColors.overlayAuto(0.08))
                        .frame(height: 56)

                    preview
                }

                VStack(spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                    .fill(AdaptiveColors.overlayAuto(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.5) : AdaptiveColors.overlayAuto(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }
}

private struct NotchGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.height * 0.45
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CompactSignalToggle: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(DroppyAnimation.hoverQuick) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn ? Color(red: 0.20, green: 0.55, blue: 0.97) : .secondary)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOn ? Color(red: 0.18, green: 0.67, blue: 0.39) : .secondary.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous)
                    .fill(AdaptiveColors.overlayAuto(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous)
                    .stroke(isOn ? Color(red: 0.20, green: 0.55, blue: 0.97).opacity(0.25) : AdaptiveColors.overlayAuto(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TinyBadge: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AdaptiveColors.overlayAuto(0.08))
        .clipShape(Capsule())
    }
}

private struct FlexibleBadgeWrap: View {
    let items: [String]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 112), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AdaptiveColors.overlayAuto(0.08))
                    .clipShape(Capsule())
            }
        }
    }
}

private struct QuickGuideLine: View {
    let action: String
    let result: String

    var body: some View {
        HStack(spacing: 8) {
            Text(action)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.quaternary)

            Text(result)
                .font(.system(size: 11, weight: .semibold))
        }
    }
}
