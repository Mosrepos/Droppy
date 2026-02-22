//
//  DonateView.swift
//  Droppy
//
//  Created by Codex on 22/02/2026.
//

import SwiftUI

struct DonateView: View {
    @AppStorage(AppPreferenceKey.useTransparentBackground) private var useTransparentBackground = PreferenceDefault.useTransparentBackground
    @Environment(\.openURL) private var openURL

    private let donationURL = URL(string: "https://buymeacoffee.com/droppy")!

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.95, green: 0.60, blue: 0.20).opacity(0.16))
                        .frame(width: 74, height: 74)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color(red: 0.95, green: 0.60, blue: 0.20))
                }

                Text("Support Droppy")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()
                .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 12) {
                Text("Donating helps keep Droppy alive, and gives you the opportunity to forward feature requests that get priority.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.9))

                Text("If you'd like anything in particular, donating puts you first in line and I'll discuss how to implement it with you.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(AdaptiveColors.overlayAuto(0.03))
            .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                    .stroke(AdaptiveColors.overlayAuto(0.06), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()
                .padding(.horizontal, 20)

            HStack(spacing: 10) {
                Button {
                    DonateWindowController.shared.closeWindow()
                } label: {
                    Text("Close")
                }
                .buttonStyle(DroppyPillButtonStyle(size: .small))

                Spacer()

                Button {
                    openURL(donationURL)
                    DonateWindowController.shared.closeWindow()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "heart.fill")
                        Text("Donate Now")
                    }
                }
                .buttonStyle(DroppyAccentButtonStyle(color: Color(red: 0.95, green: 0.60, blue: 0.20), size: .small))
            }
            .padding(DroppySpacing.lg)
        }
        .frame(width: 400)
        .fixedSize(horizontal: true, vertical: true)
        .droppyTransparentBackground(useTransparentBackground)
        .clipShape(RoundedRectangle(cornerRadius: DroppyRadius.xl, style: .continuous))
    }
}
