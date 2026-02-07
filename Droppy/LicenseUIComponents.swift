import SwiftUI

// MARK: - License Certificate Icon

private struct LicenseCertificateIcon: View {
    let isActivated: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            // Certificate body
            RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                .fill(Color(white: 0.18))
                .frame(width: size, height: size * 0.78)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.14, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )

            // Top accent stripe
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(isActivated ? Color.green : Color.orange)
                    .frame(height: 2.5)
                    .padding(.horizontal, size * 0.18)
                    .padding(.top, size * 0.14)

                Spacer()
            }
            .frame(width: size, height: size * 0.78)

            // Lines representing text
            VStack(spacing: 3.5) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: size * 0.52, height: 2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: size * 0.38, height: 2)
            }
            .offset(y: 2)

            // Seal / badge
            Image(systemName: isActivated ? "checkmark.seal.fill" : "seal.fill")
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(isActivated ? .green.opacity(0.7) : .orange.opacity(0.5))
                .offset(x: size * 0.16, y: size * 0.18)
        }
        .frame(width: size, height: size * 0.78)
    }
}

// MARK: - Live Preview Card (pre-activation)

struct LicenseLivePreviewCard: View {
    let email: String
    let keyDisplay: String
    let isActivated: Bool
    var accentColor: Color = .blue
    var enableInteractiveEffects: Bool = true

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 14) {
            LicenseCertificateIcon(isActivated: isActivated, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("License key:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(keyDisplay)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let email = nonEmpty(email) {
                    Text(email)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            Text(isActivated ? "Active" : "Pending")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActivated ? .green : .orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Identity Card (activated — settings & activation window)

struct LicenseIdentityCard: View {
    let title: String
    let subtitle: String
    let email: String
    let keyHint: String?
    let verifiedAt: Date?
    var accentColor: Color = .blue
    let footer: AnyView?
    var enableInteractiveEffects: Bool

    @State private var isHovering = false

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
        HStack(spacing: 14) {
            LicenseCertificateIcon(isActivated: true, size: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text("Licensed to:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(nonEmpty(email) ?? "Not provided")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let keyHint = nonEmpty(keyHint) {
                    Text("Key: \(keyHint)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            if let footer {
                footer
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
