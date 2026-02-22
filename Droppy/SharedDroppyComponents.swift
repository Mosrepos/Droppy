import SwiftUI
import AppKit

// MARK: - Sharing Services Cache
var sharingServicesCache: [String: (services: [NSSharingService], timestamp: Date)] = [:]
let sharingServicesCacheTTL: TimeInterval = 60
let sharingServicesCacheMaxEntries = 48

func clearSharingServicesCache() {
    sharingServicesCache.removeAll()
}

private func resolvedSharingServices(for items: [Any]) -> [NSSharingService] {
    // Use Objective-C dynamic dispatch to avoid deprecation warnings while preserving
    // NSSharingService-based context menu behavior.
    let selector = NSSelectorFromString("sharingServicesForItems:")
    guard NSSharingService.responds(to: selector),
          let unmanagedResult = NSSharingService.perform(selector, with: items),
          let services = unmanagedResult.takeUnretainedValue() as? [NSSharingService] else {
        return []
    }
    return services
}

/// Get sharing services for items with caching.
func sharingServicesForItems(_ items: [Any]) -> [NSSharingService] {
    let now = Date()
    sharingServicesCache = sharingServicesCache.filter {
        now.timeIntervalSince($0.value.timestamp) < sharingServicesCacheTTL
    }
    if sharingServicesCache.count > sharingServicesCacheMaxEntries {
        let overflow = sharingServicesCache.count - sharingServicesCacheMaxEntries
        let oldestKeys = sharingServicesCache
            .sorted { $0.value.timestamp < $1.value.timestamp }
            .prefix(overflow)
            .map { $0.key }
        for key in oldestKeys {
            sharingServicesCache.removeValue(forKey: key)
        }
    }

    // Check if first item is a URL for caching
    if let url = items.first as? URL {
        let ext = url.pathExtension.lowercased()
        if let cached = sharingServicesCache[ext],
           now.timeIntervalSince(cached.timestamp) < sharingServicesCacheTTL {
            return cached.services
        }
        let services = resolvedSharingServices(for: items)
        sharingServicesCache[ext] = (services: services, timestamp: now)
        return services
    }
    return resolvedSharingServices(for: items)
}

// MARK: - Magic Processing Overlay
/// Subtle animated overlay for background removal processing
struct MagicProcessingOverlay: View {
    let progress: Double?
    @State private var rotation: Double = 0

    init(progress: Double? = nil) {
        self.progress = progress
    }

    private var clampedProgress: Double {
        guard let progress else { return 0 }
        return min(max(progress, 0), 1)
    }
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            RoundedRectangle(cornerRadius: DroppyRadius.ml, style: .continuous)
                .fill(.black.opacity(0.5))
            
            if progress != nil {
                Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 2.5)
                    .frame(width: 24, height: 24)

                Circle()
                    .trim(from: 0, to: max(0.03, clampedProgress))
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.95), .white.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(-90))
                    .animation(DroppyAnimation.viewChange, value: clampedProgress)
            } else {
                // Subtle rotating circle for indeterminate/background processing.
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(rotation))
            }
        }
        .onAppear {
            if progress == nil {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
        }
        .onDisappear {
            // PERFORMANCE FIX: Stop repeatForever animation when removed
            withAnimation(.linear(duration: 0)) {
                rotation = 0
            }
        }
    }
}
