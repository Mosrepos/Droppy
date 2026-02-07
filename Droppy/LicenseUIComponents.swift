import SwiftUI

// MARK: - Shared card chrome (the "physical card" frame)

private struct LicenseCardChrome<Content: View>: View {
    let isActivated: Bool
    @ViewBuilder let content: () -> Content

    @State private var sealRotation: Double = 0

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Card surface
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.105))

            // Outer border
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)

            // Inner decorative frame (certificate look)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
                .padding(5)

            // Watermark seal (subtle, bottom-right) — slowly spins
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80, weight: .thin))
                .foregroundStyle(Color.white.opacity(0.025))
                .rotationEffect(.degrees(sealRotation))
                .offset(x: -12, y: -6)
                .onAppear {
                    withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
                        sealRotation = 360
                    }
                }

            // Content
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(18)
        }
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

// MARK: - Info row helper

private struct LicenseInfoRow: View {
    let label: String
    let value: String
    var mono: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary.opacity(0.7))
                .frame(width: 64, alignment: .leading)

            Text(value)
                .font(.system(size: 12, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - License Identity Card (activated, used in settings)

struct LicenseIdentityCard: View {
    let title: String
    let subtitle: String
    let email: String
    let keyHint: String?
    let verifiedAt: Date?
    var accentColor: Color = .blue
    let footer: AnyView?
    var enableInteractiveEffects: Bool

    init(
        title: String,
        subtitle: String,
        email: String,
        keyHint: String?,
        verifiedAt: Date?,
        accentColor: Color = .blue,
        footer: AnyView? = nil,
        enableInteractiveEffects: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
        self.email = email
        self.keyHint = keyHint
        self.verifiedAt = verifiedAt
        self.accentColor = accentColor
        self.footer = footer
        self.enableInteractiveEffects = enableInteractiveEffects
    }

    var body: some View {
        LicenseCardChrome(isActivated: true) {
            // Header
            HStack(alignment: .center) {
                Text("DROPPY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)

                Text("LICENSE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.secondary)

                Spacer()

                // Status
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text("Active")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            // Info rows
            VStack(alignment: .leading, spacing: 7) {
                LicenseInfoRow(label: "Email", value: nonEmpty(email) ?? "Not provided")

                if let keyHint = nonEmpty(keyHint) {
                    LicenseInfoRow(label: "Key", value: keyHint, mono: true)
                }

                if let verifiedAt {
                    LicenseInfoRow(
                        label: "Verified",
                        value: verifiedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                }
            }
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Live Preview Card (pre-activation, updates in real-time)

struct LicenseLivePreviewCard: View {
    let email: String
    let keyDisplay: String
    let isActivated: Bool
    var accentColor: Color = .blue
    var enableInteractiveEffects: Bool = true

    var body: some View {
        LicenseCardChrome(isActivated: isActivated) {
            // Header
            HStack(alignment: .center) {
                Text("DROPPY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)

                Text("LICENSE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(.secondary)

                Spacer()

                // Status
                HStack(spacing: 5) {
                    Circle()
                        .fill(isActivated ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                    Text(isActivated ? "Active" : "Pending")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isActivated ? .green : .orange)
                }
            }

            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 0.5)
                .padding(.vertical, 10)

            // Info rows
            VStack(alignment: .leading, spacing: 7) {
                LicenseInfoRow(label: "Key", value: keyDisplay, mono: true)

                if let email = nonEmpty(email) {
                    LicenseInfoRow(label: "Email", value: email)
                }
            }
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
