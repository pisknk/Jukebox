//
//  CustomProgressSlider.swift
//  Jukebox
//
//  draggable song progress bar used on the now playing screen
//

import SwiftUI

// MARK: - Custom Progress Slider
struct CustomProgressSlider: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void
    
    @State private var dragging = false
    @State private var captured: Double? = nil
    @State private var displayed: Double? = nil
    
    private var percentage: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }
    
    var body: some View {
        GeometryReader { geometry in
            let displayedPercentage = displayed ?? percentage
            let width = geometry.size.width * min(1, max(0, CGFloat(displayedPercentage)))
            
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(.white.opacity(0.4))
                    .saturation(1.6)
                
                Rectangle()
                    .fill(.white)
                    .frame(width: width)
                    .opacity(dragging ? 0.8 : 0.4)
                    .animation(.easeInOut, value: dragging)
                    .animation(.linear(duration: 0.1), value: width)
            }
            .cornerRadius(8)
            .highPriorityGesture(DragGesture(minimumDistance: 0.0, coordinateSpace: .global)
                .onChanged { gesture in
                    dragging = true
                    
                    if captured == nil {
                        captured = percentage
                    }
                    
                    let dragWidth = geometry.size.width
                    let offset = min(dragWidth, max(-dragWidth, gesture.translation.width))
                    let moved: Double = Double(offset / dragWidth)
                    let acceleration: Double = 0.8
                    let modifier = moved * acceleration
                    
                    displayed = max(0, min(1, captured! + modifier))
                }
                .onEnded { _ in
                    dragging = false
                    
                    if let displayed = displayed {
                        onSeek(duration * displayed)
                    }
                    
                    displayed = nil
                    captured = nil
                }
            )
        }
        .frame(height: dragging ? 12 : 8)
        .shadow(color: .black.opacity(0.2), radius: dragging ? 10 : 0)
        .animation(.spring(), value: dragging)
    }
}
