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

// MARK: - Mesh Gradient Point
struct MeshPoint: Equatable {
    var position: CGPoint
    var color: Color
    
    static func == (lhs: MeshPoint, rhs: MeshPoint) -> Bool {
        lhs.position == rhs.position
    }
}

// MARK: - Animated Mesh Gradient View (MeshKit-style)
struct MeshGradientView: View {
    let colors: [Color]
    let speed: Double
    
    @State private var phase: Double = 0
    
    init(colors: [Color], speed: Double = 0.5) {
        self.colors = colors
        self.speed = speed
    }
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate * speed
            
            Canvas { context, size in
                // create a 3x3 mesh grid of colors
                let gridSize = 3
                var points: [[MeshPoint]] = []
                
                for row in 0..<gridSize {
                    var rowPoints: [MeshPoint] = []
                    for col in 0..<gridSize {
                        let colorIndex = row * gridSize + col
                        let color = colorIndex < colors.count ? colors[colorIndex] : colors[colorIndex % max(1, colors.count)]
                        
                        // base position
                        let baseX = CGFloat(col) / CGFloat(gridSize - 1)
                        let baseY = CGFloat(row) / CGFloat(gridSize - 1)
                        
                        // animated offset - much more movement for visible animation
                        _ = row == 1 && col == 1
                        let isEdge = row == 0 || row == gridSize - 1 || col == 0 || col == gridSize - 1
                        let isCorner = (row == 0 || row == gridSize - 1) && (col == 0 || col == gridSize - 1)
                        
                        // corners barely move, edges move a little, center moves a lot
                        let movementScale: CGFloat = isCorner ? 0.08 : (isEdge ? 0.20 : 0.35)
                        
                        let phaseOffset = Double(colorIndex) * 0.9
                        
                        // use multiple sine waves for more organic, fluid movement
                        // lower frequencies for smoother animation
                        let wave1 = sin(time * 0.35 + phaseOffset)
                        let wave2 = sin(time * 0.55 + phaseOffset * 1.5) * 0.5
                        let wave3 = cos(time * 0.25 + phaseOffset * 0.7) * 0.3
                        
                        let xOffset = (wave1 + wave2) * movementScale
                        let yOffset = (wave3 + cos(time * 0.4 + phaseOffset)) * movementScale
                        
                        let x = (baseX + xOffset) * size.width
                        let y = (baseY + yOffset) * size.height
                        
                        rowPoints.append(MeshPoint(position: CGPoint(x: x, y: y), color: color))
                    }
                    points.append(rowPoints)
                }
                
                // draw interpolated mesh using overlapping gradients
                for row in 0..<(gridSize - 1) {
                    for col in 0..<(gridSize - 1) {
                        // get four corners of this cell
                        let topLeft = points[row][col]
                        let topRight = points[row][col + 1]
                        let bottomLeft = points[row + 1][col]
                        let bottomRight = points[row + 1][col + 1]
                        
                        // draw cell with blended gradient
                        drawMeshCell(
                            context: context,
                            topLeft: topLeft,
                            topRight: topRight,
                            bottomLeft: bottomLeft,
                            bottomRight: bottomRight,
                            size: size,
                            time: time
                        )
                    }
                }
            }
        }
        .background(
            // use darkened version of first color as base background
            colors.first?.opacity(0.6) ?? Color.black
        )
        .blur(radius: 50)
    }
    
    private func drawMeshCell(
        context: GraphicsContext,
        topLeft: MeshPoint,
        topRight: MeshPoint,
        bottomLeft: MeshPoint,
        bottomRight: MeshPoint,
        size: CGSize,
        time: Double
    ) {
        // create a path for this cell
        let path = Path { p in
            p.move(to: topLeft.position)
            p.addLine(to: topRight.position)
            p.addLine(to: bottomRight.position)
            p.addLine(to: bottomLeft.position)
            p.closeSubpath()
        }
        
        // calculate center point
        let centerX = (topLeft.position.x + topRight.position.x + bottomLeft.position.x + bottomRight.position.x) / 4
        let centerY = (topLeft.position.y + topRight.position.y + bottomLeft.position.y + bottomRight.position.y) / 4
        let center = CGPoint(x: centerX, y: centerY)
        
        // animated opacity for pulsing effect
        let pulseOpacity = 0.8 + sin(time * 2.0) * 0.15
        
        // blend all four colors with pulsing
        let gradient = Gradient(stops: [
            .init(color: topLeft.color.opacity(pulseOpacity), location: 0.0),
            .init(color: topRight.color.opacity(pulseOpacity * 0.9), location: 0.33),
            .init(color: bottomLeft.color.opacity(pulseOpacity * 0.9), location: 0.66),
            .init(color: bottomRight.color.opacity(pulseOpacity), location: 1.0)
        ])
        
        // draw radial gradient in cell
        let radius = max(size.width, size.height) * 0.6
        context.fill(path, with: .radialGradient(
            gradient,
            center: center,
            startRadius: 0,
            endRadius: radius
        ))
        
        // draw additional corner gradients for smoother blending with animated sizes
        let points = [topLeft, topRight, bottomLeft, bottomRight]
        for (index, point) in points.enumerated() {
            let sizeWave = 0.35 + sin(time * 1.5 + Double(index) * 0.8) * 0.1
            let opacityWave = 0.5 + sin(time * 1.2 + Double(index) * 1.1) * 0.2
            
            let cornerGradient = Gradient(colors: [
                point.color.opacity(opacityWave),
                point.color.opacity(0.0)
            ])
            
            let cornerPath = Path(ellipseIn: CGRect(
                x: point.position.x - size.width * sizeWave,
                y: point.position.y - size.height * sizeWave,
                width: size.width * sizeWave * 2,
                height: size.height * sizeWave * 2
            ))
            
            context.fill(cornerPath, with: .radialGradient(
                cornerGradient,
                center: point.position,
                startRadius: 0,
                endRadius: size.width * sizeWave
            ))
        }
    }
}

// MARK: - Album Art Mesh Gradient
struct AlbumFluidGradient: View {
    let image: UIImage?
    
    @State private var extractedColors: [Color] = []
    
    var body: some View {
        Group {
            if extractedColors.isEmpty {
                MeshGradientView(colors: UIImage.defaultGradientColors(), speed: 0.5)
            } else {
                MeshGradientView(colors: extractedColors, speed: 0.5)
            }
        }
        .ignoresSafeArea()
        .onChange(of: image) { newImage in
            updateColors(from: newImage)
        }
        .onAppear {
            updateColors(from: image)
        }
    }
    
    private func updateColors(from image: UIImage?) {
        if let img = image {
            DispatchQueue.global(qos: .userInitiated).async {
                let colors = img.extractDominantColors(count: 9)
                DispatchQueue.main.async {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        extractedColors = colors
                    }
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
    
    init(colors: [Color], speed: Double = 0.5, blur: CGFloat = 80) {
        self.colors = colors
        self.speed = speed
        self.blur = blur
    }
    
    var body: some View {
        MeshGradientView(colors: colors, speed: speed)
    }
}
