//
//  UpdateView.swift
//  Droppy
//
//  Created by Jordy Spruit on 04/01/2026.
//

import SwiftUI

struct UpdateView: View {
    @ObservedObject var checker = UpdateChecker.shared
    @State private var hoverLocation: CGPoint = .zero
    @State private var isBgHovering: Bool = false
    @AppStorage("useTransparentBackground") private var useTransparentBackground = false
    
    // Matched state from Clipboard Preview
    @State private var isUpdateHovering = false
    @State private var isLaterHovering = false
    @State private var isOkHovering = false
    
    // Computed properties for cleaner conditions
    private var isUpToDate: Bool { checker.showingUpToDate }
    private var windowHeight: CGFloat { isUpToDate ? 200 : 450 }
    
    var body: some View {
        VStack(spacing: isUpToDate ? 20 : 24) {
            // Header
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .liquidGlass(radius: 14, depth: 1.2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(isUpToDate ? "Droppy is up to date!" : "Update Available")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    
                    if isUpToDate {
                        Text("You're running the latest version (\(checker.currentVersion)).")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.8))
                    } else if let newVersion = checker.latestVersion {
                        Text("Version \(newVersion) is available. You are on \(checker.currentVersion).")
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .background(WindowDragArea())
            
            // Release Notes - Only show when update available
            if !isUpToDate {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let notes = checker.releaseNotes {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Array(notes.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                                    if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                                        if let attributed = try? AttributedString(markdown: line) {
                                            Text(attributed)
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white.opacity(0.9))
                                                .textSelection(.enabled)
                                        } else {
                                            Text(line)
                                                .font(.system(size: 14))
                                                .foregroundStyle(.white.opacity(0.9))
                                                .textSelection(.enabled)
                                        }
                                    } else {
                                        // Handle empty lines (spacing between paragraphs)
                                        Spacer().frame(height: 8)
                                    }
                                }
                            }
                        } else {
                            Text("No release notes available.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            }
            
            // Actions
            HStack(spacing: 12) {
                if isUpToDate {
                    Spacer()
                    
                    // Single "OK" button for up to date state
                    Button {
                        UpdateWindowController.shared.closeWindow()
                    } label: {
                        Text("OK")
                            .fontWeight(.semibold)
                            .frame(width: 80)
                            .padding(.vertical, 12)
                            .background(Color.blue.opacity(isOkHovering ? 1.0 : 0.8))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                            .scaleEffect(isOkHovering ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isOkHovering = h } }
                } else {
                    // Secondary "Later" Button
                    Button {
                        UpdateWindowController.shared.closeWindow()
                    } label: {
                        Text("Later")
                            .fontWeight(.medium)
                            .frame(width: 80)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(isLaterHovering ? 0.2 : 0.1))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                            .scaleEffect(isLaterHovering ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isLaterHovering = h } }
                    
                    Spacer()
                    
                    // Primary "Update & Restart" Button
                    Button {
                        if let url = checker.downloadURL {
                            AutoUpdater.shared.installUpdate(from: url)
                            UpdateWindowController.shared.closeWindow()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Update & Restart")
                        }
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(isUpdateHovering ? 1.0 : 0.8))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .scaleEffect(isUpdateHovering ? 1.02 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .onHover { h in withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isUpdateHovering = h } }
                }
            }
        }
        .padding(24)
        .frame(width: 500, height: windowHeight)
        .background(useTransparentBackground ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Color.black))
        .background {
            if useTransparentBackground {
                Color.clear
                    .liquidGlass(shape: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
        .overlay { 
            HexagonDotsEffect(
                mouseLocation: hoverLocation, 
                isHovering: isBgHovering, 
                coordinateSpaceName: "updateWindow"
            ) 
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .coordinateSpace(name: "updateWindow")
        .onContinuousHover(coordinateSpace: .named("updateWindow")) { phase in
            handleHover(phase)
        }
    }
    
    private func handleHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            hoverLocation = location
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isBgHovering = true }
        case .ended:
            withAnimation(.linear(duration: 0.2)) { isBgHovering = false }
        }
    }
}

