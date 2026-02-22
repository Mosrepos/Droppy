//
//  AIInstallView.swift
//  Droppy
//
//  Native installation window for AI background removal
//  Design matches DroppyUpdater for visual consistency
//

import SwiftUI

// MARK: - Install Step Model

enum AIInstallStep: Int, CaseIterable {
    case checking = 0
    case downloading
    case installing
    case complete

    var title: String {
        switch self {
        case .checking: return "Checking runtime…"
        case .downloading: return "Downloading model…"
        case .installing: return "Validating model…"
        case .complete: return "Installation Complete!"
        }
    }

    var icon: String {
        switch self {
        case .checking: return "magnifyingglass"
        case .downloading: return "arrow.down.circle"
        case .installing: return "checkmark.shield"
        case .complete: return "checkmark.circle.fill"
        }
    }
}

// MARK: - Install View

struct AIInstallView: View {
    @ObservedObject var manager = AIInstallManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.droppyPanelCloseAction) private var panelCloseAction

    @State private var pulseAnimation = false
    @State private var showSuccessGlow = false
    @State private var showConfetti = false
    @State private var currentStep: AIInstallStep = .checking

    // Stats passed from parent
    var installCount: Int?

    private var isFailureState: Bool {
        manager.installError != nil && !manager.isInstalling && !manager.isInstalled
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                headerSection

                Divider()
                    .padding(.horizontal, 24)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        contentSection

                        if let error = manager.installError {
                            errorSection(error: error)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .frame(maxHeight: 400)

                Divider()
                    .padding(.horizontal, 24)

                buttonSection
            }

            if showConfetti {
                AIConfettiView()
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 450)
        .fixedSize(horizontal: true, vertical: true)
        .droppyLiquidPopoverSurface(cornerRadius: DroppyRadius.xl)
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.xl, style: .continuous))
        .onAppear {
            pulseAnimation = true
            manager.checkInstallationStatus()
        }
        .onChange(of: manager.isInstalled) { _, installed in
            if installed && !manager.isInstalling {
                currentStep = .complete
                showSuccessGlow = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showConfetti = true
                }
            }
        }
        .onChange(of: manager.installProgress) { _, progress in
            if progress.contains("Checking") {
                currentStep = .checking
            } else if progress.contains("Downloading") {
                currentStep = .downloading
            } else if progress.contains("Validating") {
                currentStep = .installing
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                if manager.isInstalled && !manager.isInstalling {
                    Circle()
                        .stroke(Color.green.opacity(0.6), lineWidth: 3)
                        .frame(width: 76, height: 76)
                        .scaleEffect(showSuccessGlow ? 1.3 : 1.0)
                        .opacity(showSuccessGlow ? 0 : 1)
                        .animation(DroppyAnimation.transition, value: showSuccessGlow)
                }

                if manager.isInstalling {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .cyan.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)
                        .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                        .opacity(pulseAnimation ? 0 : 0.5)
                        .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false), value: pulseAnimation)
                }

                CachedAsyncImage(url: URL(string: "https://getdroppy.app/assets/icons/ai-bg.jpg")) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Image(systemName: "brain.head.profile").font(.system(size: 32)).foregroundStyle(.blue)
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.large, style: .continuous))
                .shadow(color: manager.isInstalled ? .green.opacity(0.4) : .blue.opacity(0.3), radius: 8, y: 4)
                .scaleEffect(manager.isInstalled ? 1.05 : 1.0)
                .animation(DroppyAnimation.stateEmphasis, value: manager.isInstalled)
            }

            Text(statusTitle)
                .font(.title2.bold())
                .foregroundStyle(manager.isInstalled ? .green : (isFailureState ? .orange : .primary))

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12))
                    Text(AnalyticsService.shared.isDisabled ? "–" : "\(installCount ?? 0)")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.secondary)


                Text("AI")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.15)))
            }

            Text("BiRefNet - External Runtime")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var statusTitle: String {
        if isFailureState {
            return "Setup Needs Attention"
        } else if manager.isInstalled && !manager.isInstalling {
            return "Installed & Ready"
        } else if manager.isInstalling {
            return "Installing…"
        } else {
            return "AI Background Removal"
        }
    }

    // MARK: - Content

    private var contentSection: some View {
        Group {
            if manager.isInstalling || manager.isInstalled || isFailureState {
                stepsView
            } else {
                featuresView
            }
        }
    }

    private var stepsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(AIInstallStep.allCases.filter { $0 != .complete }, id: \.rawValue) { step in
                AIStepRow(
                    step: step,
                    currentStep: currentStep,
                    isAllComplete: manager.isInstalled && !manager.isInstalling,
                    hasError: manager.installError != nil
                )
            }

            if manager.isInstalling && !manager.installProgress.isEmpty {
                installProgressView
                    .padding(.leading, 32)
                    .padding(.top, 10)
            } else if isFailureState {
                Text("Install stopped before completion. Retry install or press Re-check.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 32)
                    .padding(.top, 8)
            }
        }
        .padding(.bottom, 20)
    }

    private var installProgressView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(Int(manager.installProgressFraction * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous)
                            .fill(Color.blue.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DroppyRadius.ms, style: .continuous)
                            .stroke(AdaptiveColors.overlayAuto(0.08), lineWidth: 1)
                    )

                Spacer()

                if !manager.installProgressDetail.isEmpty {
                    Text(manager.installProgressDetail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DroppyRadius.sm, style: .continuous)
                    .fill(Color.blue.opacity(0.28))
                    .frame(height: 8)

                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: DroppyRadius.sm, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * max(0.015, manager.installProgressFraction))
                        .animation(DroppyAnimation.viewChange, value: manager.installProgressFraction)
                }
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity)

            Text(manager.installProgress)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var featuresView: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow(icon: "sparkles", text: "Best-in-class background removal")
            featureRow(icon: "bolt.fill", text: "BiRefNet external runtime inference")
            featureRow(icon: "lock.fill", text: "100% on-device processing")
            featureRow(icon: "arrow.down.circle", text: "One-time runtime + model download (~1 GB)")

            CachedAsyncImage(url: URL(string: "https://getdroppy.app/assets/images/ai-bg-screenshot.png")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                            .strokeBorder(AdaptiveColors.subtleBorderAuto, lineWidth: 1)
                    )
                    .padding(.top, 8)
            } placeholder: {
                EmptyView()
            }
        }
        .padding(.bottom, 20)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: 24)

            Text(text)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }

    private func errorSection(error: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Install Needs Attention")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(error)
                .font(.caption)
                .foregroundStyle(.primary)

            Text("Retry install, or press Re-check after network/storage issues are resolved.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    manager.checkInstallationStatus()
                } label: {
                    Label("Re-check", systemImage: "arrow.clockwise")
                }
                .buttonStyle(DroppyPillButtonStyle(size: .small))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DroppySpacing.md)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                .stroke(AdaptiveColors.overlayAuto(0.12), lineWidth: 1)
        )
        .padding(.bottom, 16)
    }

    // MARK: - Buttons

    private var buttonSection: some View {
        HStack(spacing: 10) {
            if !manager.isInstalling {
                Button {
                    closePanelOrDismiss(panelCloseAction, dismiss: dismiss)
                } label: {
                    Text(manager.isInstalled ? "Close" : "Cancel")
                }
                .buttonStyle(DroppyPillButtonStyle(size: .small))
            }

            Spacer()

            if !manager.isInstalled && !manager.isInstalling {
                Button {
                    Task {
                        currentStep = .checking
                        await manager.installTransparentBackground()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: manager.installError == nil ? "arrow.down.circle.fill" : "arrow.clockwise")
                        Text(manager.installError == nil ? "Install Now" : "Retry Install")
                    }
                }
                .buttonStyle(DroppyAccentButtonStyle(color: AdaptiveColors.selectionBlueAuto, size: .medium))
            }

            DisableExtensionButton(extensionType: .aiBackgroundRemoval)
        }
        .padding(DroppySpacing.lg)
        .animation(DroppyAnimation.transition, value: manager.isInstalled)
    }
}

#Preview {
    AIInstallView()
        .frame(width: 340, height: 400)
}
