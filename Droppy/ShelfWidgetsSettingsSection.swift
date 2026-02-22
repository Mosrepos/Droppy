import SwiftUI
import UniformTypeIdentifiers

struct ShelfWidgetsSettingsSection: View {
    private var manager = ShelfWidgetsManager.shared
    @State private var selectedProfile: ShelfLayoutProfileType = .builtIn
    @State private var draggedPlacementID: UUID?

    private var profile: ShelfProfileConfiguration {
        manager.profile(for: selectedProfile)
    }

    private var activePage: ShelfPageConfiguration {
        manager.activePage(for: selectedProfile)
    }

    var body: some View {
        Group {
            Section {
                Picker("Layout Profile", selection: $selectedProfile) {
                    Text("Built-in Display").tag(ShelfLayoutProfileType.builtIn)
                    Text("External Displays").tag(ShelfLayoutProfileType.external)
                }
                .pickerStyle(.segmented)

                if manager.showOnboardingCallouts {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("New: Shelf Widgets")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Create up to 4 pages, drag widgets to reorder, and swipe between pages in the expanded shelf.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button("Dismiss") {
                            manager.dismissOnboardingCallouts()
                        }
                        .buttonStyle(DroppyPillButtonStyle(size: .small))
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AdaptiveColors.overlayAuto(0.05))
                    )
                }
            } header: {
                Text("Shelf Widgets")
            } footer: {
                Text("Layouts are saved separately for built-in and external displays.")
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(profile.pages) { page in
                            let isActive = page.id == activePage.id
                            Button {
                                manager.setActivePage(index: page.index, for: selectedProfile)
                            } label: {
                                Text("Page \(page.index + 1)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(isActive ? AdaptiveColors.selectionBlueAuto.opacity(0.92) : AdaptiveColors.overlayAuto(0.08))
                                    )
                                    .foregroundStyle(isActive ? Color.white : AdaptiveColors.primaryTextAuto)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack(spacing: 8) {
                    Button("Add Page") {
                        _ = manager.addPage(for: selectedProfile)
                    }
                    .buttonStyle(DroppyPillButtonStyle(size: .small))
                    .disabled(profile.pages.count >= 4)

                    Button("Remove Page") {
                        _ = manager.removeActivePage(for: selectedProfile)
                    }
                    .buttonStyle(DroppyPillButtonStyle(size: .small))
                    .disabled(profile.pages.count <= 1)

                    Spacer(minLength: 0)

                    Button("Undo") {
                        manager.undoLastChange()
                    }
                    .buttonStyle(DroppyPillButtonStyle(size: .small))
                }
            } header: {
                Text("Pages")
            } footer: {
                Text("Pages cannot be empty and are limited to 4.")
            }

            Section {
                if activePage.placements.isEmpty {
                    Text("No widgets on this page")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(activePage.placements.sorted(by: { $0.order < $1.order })) { placement in
                            ShelfWidgetPlacementRow(
                                profileType: selectedProfile,
                                pageID: activePage.id,
                                placement: placement,
                                draggedPlacementID: $draggedPlacementID
                            )
                        }
                    }
                }
            } header: {
                Text("Page Layout")
            } footer: {
                Text("Drag rows to reorder. Size hints are used by the adaptive layout engine.")
            }

            Section {
                VStack(spacing: 8) {
                    ForEach(ShelfWidgetsRegistry.descriptors) { descriptor in
                        let used = profile.pages
                            .flatMap(\.placements)
                            .contains(where: { $0.type == descriptor.type })
                        let availability = ShelfWidgetsRegistry.availability(for: descriptor.type)

                        HStack(spacing: 10) {
                            Label(descriptor.title, systemImage: descriptor.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AdaptiveColors.primaryTextAuto)

                            Spacer(minLength: 0)

                            if used {
                                Text("Added")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            } else if availability.isAvailable {
                                Button("Add") {
                                    _ = manager.addWidget(descriptor.type, to: activePage.id, profile: selectedProfile)
                                }
                                .buttonStyle(DroppyPillButtonStyle(size: .small))
                            } else {
                                Text(availability.reason ?? "Unavailable")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Widget Library")
            } footer: {
                Text("Each widget can be used once per display profile.")
            }
        }
    }
}

private struct ShelfWidgetPlacementRow: View {
    let profileType: ShelfLayoutProfileType
    let pageID: UUID
    let placement: ShelfWidgetPlacement
    @Binding var draggedPlacementID: UUID?

    let manager = ShelfWidgetsManager.shared

    var body: some View {
        let descriptor = ShelfWidgetsRegistry.descriptor(for: placement.type)
        let availability = ShelfWidgetsRegistry.availability(for: placement.type)

        HStack(spacing: 10) {
            Image(systemName: descriptor.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(availability.isAvailable ? AdaptiveColors.selectionBlueAuto : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.primaryTextAuto)
                if !availability.isAvailable, let reason = availability.reason {
                    Text(reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Picker("Size", selection: Binding(
                get: { placement.sizeHint },
                set: { manager.setSizeHint($0, for: placement.id, on: pageID, profile: profileType) }
            )) {
                Text("S").tag(ShelfWidgetSizeHint.small)
                Text("M").tag(ShelfWidgetSizeHint.medium)
                Text("L").tag(ShelfWidgetSizeHint.large)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 110)

            Button {
                manager.removeWidget(placementID: placement.id, from: pageID, profile: profileType)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AdaptiveColors.overlayAuto(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(AdaptiveColors.overlayAuto(0.08), lineWidth: 1)
        )
        .onDrag {
            draggedPlacementID = placement.id
            return NSItemProvider(object: placement.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.text.identifier], delegate: ShelfWidgetPlacementDropDelegate(
            destinationPlacementID: placement.id,
            pageID: pageID,
            profileType: profileType,
            draggedPlacementID: $draggedPlacementID
        ))
    }
}

private struct ShelfWidgetPlacementDropDelegate: DropDelegate {
    let destinationPlacementID: UUID
    let pageID: UUID
    let profileType: ShelfLayoutProfileType
    @Binding var draggedPlacementID: UUID?

    let manager = ShelfWidgetsManager.shared

    func performDrop(info: DropInfo) -> Bool {
        draggedPlacementID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedPlacementID else { return }
        guard draggedPlacementID != destinationPlacementID else { return }
        manager.moveWidget(
            placementID: draggedPlacementID,
            to: destinationPlacementID,
            on: pageID,
            profile: profileType
        )
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
