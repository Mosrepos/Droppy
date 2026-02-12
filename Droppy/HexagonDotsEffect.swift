//
//  HexagonDotsEffect.swift
//  Droppy
//
//  Created by Jordy Spruit on 02/01/2026.
//

import SwiftUI

// MARK: - Hexagon Dots Effect
struct HexagonDotsEffect: View {
    var isExpanded: Bool = false
    var mouseLocation: CGPoint
    var isHovering: Bool
    var coordinateSpaceName: String = "shelfContainer"
    
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                // Early exit if size is invalid
                guard size.width > 0 && size.height > 0 else { return }
                
                // Coordinate transformation:
                // mouseLocation is in the named coordinate space.
                // We need to convert it to local space.
                let myFrame = proxy.frame(in: .named(coordinateSpaceName))
                let localMouse = CGPoint(
                    x: mouseLocation.x - myFrame.minX,
                    y: mouseLocation.y - myFrame.minY
                )
                
                let spacing: CGFloat = 10 // Slightly larger spacing for fewer draw calls
                let radius: CGFloat = 0.8
                let hexHeight = spacing * sqrt(3) / 2
                let limit: CGFloat = 80
                let limitSquared = limit * limit
                let baseOpacity: CGFloat = 0.015

                let cols = min(Int(size.width / spacing) + 2, 200) // Cap max columns
                let rows = min(Int(size.height / hexHeight) + 2, 200) // Cap max rows
                
                for row in 0..<rows {
                    for col in 0..<cols {
                        let xOffset = (row % 2 == 0) ? 0 : spacing / 2
                        let x = CGFloat(col) * spacing + xOffset
                        let y = CGFloat(row) * hexHeight
                        
                        let point = CGPoint(x: x, y: y)
                        let dx = point.x - localMouse.x
                        let dy = point.y - localMouse.y
                        let distanceSquared = dx * dx + dy * dy
                        
                        // Effect logic
                        if isHovering && distanceSquared < limitSquared {
                            let intensity = 1 - (sqrt(distanceSquared) / limit)
                            let scale = 1 + (intensity * 0.5)
                            let opacity = 0.02 + (intensity * 0.13)
                            
                            let rect = CGRect(
                                x: x - radius * scale,
                                y: y - radius * scale,
                                width: radius * 2 * scale,
                                height: radius * 2 * scale
                            )
                            
                            context.opacity = opacity
                            let path = Circle().path(in: rect)
                            context.fill(path, with: .color(.white))
                            
                        } else {
                            // Base state
                            context.opacity = baseOpacity
                            let rect = CGRect(
                                x: x - radius,
                                y: y - radius,
                                width: radius * 2,
                                height: radius * 2
                            )
                            let path = Circle().path(in: rect)
                            context.fill(path, with: .color(.white))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .animation(nil, value: mouseLocation) // Disable animations for this view to prevent lag
    }
}
