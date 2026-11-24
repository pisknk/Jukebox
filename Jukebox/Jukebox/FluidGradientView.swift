//
//  FluidGradientView.swift
//  Jukebox
//
//  A mesh gradient background that extracts colors from album artwork.
//  Inspired by MeshKit - uses Metal for smooth mesh gradient rendering.
//

import SwiftUI
import UIKit

// MARK: - Advanced Color Extraction
extension UIImage {
    /// extracts dominant colors from the image
    func extractDominantColors(count: Int = 9) -> [Color] {
        guard let cgImage = self.cgImage else {
            return UIImage.defaultGradientColors()
        }
        
        let width = 100
        let height = 100
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 4 * width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return UIImage.defaultGradientColors()
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var colorBuckets: [String: (r: Double, g: Double, b: Double, count: Int)] = [:]
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = 4 * (y * width + x)
                let r = Double(rawData[offset]) / 255.0
                let g = Double(rawData[offset + 1]) / 255.0
                let b = Double(rawData[offset + 2]) / 255.0
                let a = Double(rawData[offset + 3]) / 255.0
                
                guard a > 0.5 else { continue }
                
                let brightness = (r + g + b) / 3.0
                guard brightness > 0.08 && brightness < 0.95 else { continue }
                
                let qr = Int(r * 12) * 21
                let qg = Int(g * 12) * 21
                let qb = Int(b * 12) * 21
                let key = "\(qr)-\(qg)-\(qb)"
                
                if var existing = colorBuckets[key] {
                    existing.r += r
                    existing.g += g
                    existing.b += b
                    existing.count += 1
                    colorBuckets[key] = existing
                } else {
                    colorBuckets[key] = (r: r, g: g, b: b, count: 1)
                }
            }
        }
        
        var averagedColors: [(r: Double, g: Double, b: Double, count: Int)] = []
        for (_, bucket) in colorBuckets {
            let avgR = bucket.r / Double(bucket.count)
            let avgG = bucket.g / Double(bucket.count)
            let avgB = bucket.b / Double(bucket.count)
            averagedColors.append((r: avgR, g: avgG, b: avgB, count: bucket.count))
        }
        
        averagedColors.sort { a, b in
            let satA = max(a.r, a.g, a.b) - min(a.r, a.g, a.b)
            let satB = max(b.r, b.g, b.b) - min(b.r, b.g, b.b)
            return Double(a.count) * (satA + 0.3) > Double(b.count) * (satB + 0.3)
        }
        
        var extractedColors: [Color] = []
        var lastColors: [(r: Double, g: Double, b: Double)] = []
        
        for color in averagedColors {
            var isDifferent = true
            for last in lastColors {
                let diff = abs(color.r - last.r) + abs(color.g - last.g) + abs(color.b - last.b)
                if diff < 0.25 {
                    isDifferent = false
                    break
                }
            }
            
            if isDifferent {
                extractedColors.append(Color(red: color.r, green: color.g, blue: color.b))
                lastColors.append((r: color.r, g: color.g, b: color.b))
            }
            
            if extractedColors.count >= count {
                break
            }
        }
        
        while extractedColors.count < count {
            if let first = extractedColors.first {
                extractedColors.append(first.opacity(0.8))
            } else {
                extractedColors.append(Color.purple)
            }
        }
        
        return extractedColors
    }
    
    static func defaultGradientColors() -> [Color] {
        return [
            Color(red: 0.5, green: 0.3, blue: 0.7),
            Color(red: 0.3, green: 0.5, blue: 0.8),
            Color(red: 0.6, green: 0.4, blue: 0.6),
            Color(red: 0.4, green: 0.3, blue: 0.5),
            Color(red: 0.5, green: 0.5, blue: 0.7),
            Color(red: 0.3, green: 0.4, blue: 0.6),
            Color(red: 0.6, green: 0.3, blue: 0.5),
            Color(red: 0.4, green: 0.5, blue: 0.6),
            Color(red: 0.5, green: 0.4, blue: 0.5)
        ]
    }
}

// MARK: - Smooth Animated Mesh Gradient View
struct MeshGradientView: View {
    let colors: [Color]
    let speed: Double
    let isAnimating: Bool
    
    @State private var animationProgress: CGFloat = 0
    
    init(colors: [Color], speed: Double = 0.5, isAnimating: Bool = true) {
        self.colors = colors
        self.speed = speed
        self.isAnimating = isAnimating
    }
    
    var body: some View {
        // 30fps is plenty for a heavily blurred background and halves the GPU work
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate * speed
            
            Canvas { context, size in
                // draw a 3x3 grid of animated color blobs
                let gridSize = 3
                
                for row in 0..<gridSize {
                    for col in 0..<gridSize {
                        let colorIndex = (row * gridSize + col) % colors.count
                        let color = colors[colorIndex]
                        
                        // base grid position
                        let baseX = (CGFloat(col) + 0.5) / CGFloat(gridSize) * size.width
                        let baseY = (CGFloat(row) + 0.5) / CGFloat(gridSize) * size.height
                        
                        // smooth wave animation for each point - faster movement
                        let phaseOffset = Double(row * gridSize + col) * 0.8
                        let wave1 = Darwin.sin(time * 1.2 + phaseOffset)
                        let wave2 = Darwin.cos(time * 0.9 + phaseOffset * 1.3)
                        let wave3 = Darwin.sin(time * 0.7 + phaseOffset * 0.5)
                        
                        // calculate animated position with more noticeable movement
                        let moveRange = min(size.width, size.height) * 0.25
                        let x = baseX + CGFloat(wave1 + wave3 * 0.5) * moveRange
                        let y = baseY + CGFloat(wave2 + wave3 * 0.3) * moveRange
                        
                        // draw large overlapping radial gradient
                        let blobRadius = max(size.width, size.height) * 0.5
                        let rect = CGRect(
                            x: x - blobRadius,
                            y: y - blobRadius,
                            width: blobRadius * 2,
                            height: blobRadius * 2
                        )
                        
                        let gradient = Gradient(colors: [
                            color.opacity(0.85),
                            color.opacity(0.4),
                            color.opacity(0.0)
                        ])
                        
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .radialGradient(
                                gradient,
                                center: CGPoint(x: x, y: y),
                                startRadius: 0,
                                endRadius: blobRadius
                            )
                        )
                    }
                }
            }
        }
        .background(colors.first?.opacity(0.7) ?? Color.black)
        .blur(radius: 40)
        .drawingGroup() // rasterize for smoother performance
    }
}

// MARK: - Album Art Mesh Gradient
struct AlbumFluidGradient: View {
    let image: UIImage?
    /// identifies the artwork (e.g. the song's persistent id). colours are only re-extracted
    /// when this changes, not every time the view redraws with a new UIImage instance.
    var imageID: UInt64? = nil
    var isAnimating: Bool = true

    @State private var extractedColors: [Color] = []
    @State private var activeID: UInt64? = nil

    /// colours already worked out, keyed by imageID
    private static var colorCache: [UInt64: [Color]] = [:]

    var body: some View {
        Group {
            if extractedColors.isEmpty {
                MeshGradientView(colors: UIImage.defaultGradientColors(), speed: 0.5, isAnimating: isAnimating)
            } else {
                MeshGradientView(colors: extractedColors, speed: 0.5, isAnimating: isAnimating)
            }
        }
        .ignoresSafeArea()
        .onChange(of: imageID) { _ in
            updateColors()
        }
        .onAppear {
            updateColors()
        }
    }

    private func updateColors() {
        activeID = imageID
        if let id = imageID, let cached = Self.colorCache[id] {
            withAnimation(.easeInOut(duration: 0.8)) { extractedColors = cached }
            return
        }
        guard let img = image else { return }
        let id = imageID
        DispatchQueue.global(qos: .userInitiated).async {
            let colors = img.extractDominantColors(count: 9)
            DispatchQueue.main.async {
                if let id = id {
                    if Self.colorCache.count > 200 { Self.colorCache.removeAll() }
                    Self.colorCache[id] = colors
                }
                // the song may have changed while we were working
                guard id == activeID else { return }
                withAnimation(.easeInOut(duration: 0.8)) {
                    extractedColors = colors
                }
            }
        }
    }
}

// MARK: - Fallback Fluid Gradient (for when no album art)
struct FluidGradientView: View {
    let colors: [Color]
    let speed: Double
    let blur: CGFloat
    var isAnimating: Bool = true
    
    init(colors: [Color], speed: Double = 0.5, blur: CGFloat = 80, isAnimating: Bool = true) {
        self.colors = colors
        self.speed = speed
        self.blur = blur
        self.isAnimating = isAnimating
    }
    
    var body: some View {
        MeshGradientView(colors: colors, speed: speed, isAnimating: isAnimating)
    }
}
