import SwiftUI
import AppKit

// MARK: - Sharing Services Cache
var sharingServicesCache: [String: (services: [NSSharingService], timestamp: Date)] = [:]
let sharingServicesCacheTTL: TimeInterval = 60

/// Wrapper function that uses the deprecated sharingServices(forItems:) API.
/// Apple recommends NSSharingServicePicker.standardShareMenuItem but that doesn't work
/// with SwiftUI context menus which require explicit ForEach over services.
/// This wrapper isolates the API call to one location.
@available(macOS, deprecated: 13.0, message: "No alternative for SwiftUI context menus")
private func _getSharingServices(_ items: [Any]) -> [NSSharingService] {
    NSSharingService.sharingServices(forItems: items)
}

/// Get sharing services for items with caching. Uses deprecated API but no alternative exists for context menus.
func sharingServicesForItems(_ items: [Any]) -> [NSSharingService] {
    // Check if first item is a URL for caching
    if let url = items.first as? URL {
        let ext = url.pathExtension.lowercased()
        if let cached = sharingServicesCache[ext],
           Date().timeIntervalSince(cached.timestamp) < sharingServicesCacheTTL {
            return cached.services
        }
        let services = _getSharingServices(items)
        sharingServicesCache[ext] = (services: services, timestamp: Date())
        return services
    }
    return _getSharingServices(items)
}

// MARK: - Magic Processing Overlay
/// Subtle animated overlay for background removal processing
struct MagicProcessingOverlay: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            RoundedRectangle(cornerRadius: DroppyRadius.ml, style: .continuous)
                .fill(.black.opacity(0.5))
            
            // Subtle rotating circle
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
        .onAppear {
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                rotation = 360
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
