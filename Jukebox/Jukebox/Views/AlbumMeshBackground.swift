//
//  AlbumMeshBackground.swift
//  Jukebox
//
//  Native Glass background for Now Playing and Lyrics: big, soft colour blobs from
//  the album artwork that slowly drift, in the style of the iOS 13 Music lyrics screen.
//
//  Built on native APIs:
//  - SwiftUI `MeshGradient` draws the blobs (GPU, no blur pass needed)
//  - Core Image `CIKMeans` picks the artwork's main colours
//
//  Amity 1.0 keeps using FluidGradientView.
//

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Palette extraction (CIKMeans)

enum ArtworkPalette {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// main colours of the image, most common first
    static func colors(from image: UIImage, count: Int = 6) -> [Color] {
        guard let cgImage = image.cgImage else { return fallback }

        // k-means doesn't need detail; a small image is plenty and much faster
        var input = CIImage(cgImage: cgImage)
        let longest = max(input.extent.width, input.extent.height)
        if longest > 96 {
            let scale = 96 / longest
            input = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        let filter = CIFilter.kMeans()
        filter.inputImage = input
        filter.extent = input.extent
        filter.count = count
        filter.passes = 10
        filter.perceptual = true
        guard let output = filter.outputImage else { return fallback }

        // output is `count` pixels wide: rgb = cluster colour, alpha = share of the image
        let bounds = CGRect(x: 0, y: 0, width: count, height: 1)
        let weights = render(output, bounds: bounds, count: count).map { $0[3] }
        let colors = render(output.settingAlphaOne(in: bounds), bounds: bounds, count: count)

        let clusters = zip(colors, weights)
            .filter { $0.1 > 0.01 }
            .sorted { $0.1 > $1.1 }
            .map { Color(.sRGB, red: Double($0.0[0]), green: Double($0.0[1]), blue: Double($0.0[2])) }

        return clusters.isEmpty ? fallback : clusters
    }

    private static func render(_ image: CIImage, bounds: CGRect, count: Int) -> [[Float]] {
        var pixels = [Float](repeating: 0, count: count * 4)
        context.render(image,
                       toBitmap: &pixels,
                       rowBytes: count * 4 * MemoryLayout<Float>.size,
                       bounds: bounds,
                       format: .RGBAf,
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return stride(from: 0, to: pixels.count, by: 4).map { Array(pixels[$0..<($0 + 4)]) }
    }

    static let fallback: [Color] = [
        Color(red: 0.55, green: 0.25, blue: 0.65),
        Color(red: 0.25, green: 0.35, blue: 0.75),
        Color(red: 0.85, green: 0.35, blue: 0.45),
        Color(red: 0.95, green: 0.6, blue: 0.3)
    ]
}

// MARK: - Animated mesh

@available(iOS 26, *)
struct AlbumMeshBackground: View {
    let image: UIImage?
    /// identifies the artwork (the song's persistent id); colours are only worked out when it changes
    let imageID: UInt64?
    var isAnimating: Bool = true

    @State private var palette: [Color] = ArtworkPalette.fallback
    @State private var activeID: UInt64? = nil

    private static var cache: [UInt64: [Color]] = [:]
    private static let gridSize = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            MeshGradient(
                width: Self.gridSize,
                height: Self.gridSize,
                points: Self.points(at: time),
                colors: Self.gridColors(from: palette, seed: imageID ?? 0),
                background: palette.first ?? .black,
                smoothsColors: true,
                colorSpace: .perceptual
            )
        }
        // slightly darker towards the bottom so white text stays readable, like iOS 13
        .overlay(
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.15), .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .ignoresSafeArea()
        .onAppear(perform: updatePalette)
        .onChange(of: imageID) { _, _ in updatePalette() }
    }

    // MARK: points

    /// a 4x4 grid. corners stay put, edge points slide along their edge, and the four inner
    /// points wander in slow loops - that's what makes the colour blobs drift.
    private static func points(at time: TimeInterval) -> [SIMD2<Float>] {
        let t = Float(time)
        var result: [SIMD2<Float>] = []
        result.reserveCapacity(gridSize * gridSize)

        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let baseX = Float(col) / Float(gridSize - 1)
                let baseY = Float(row) / Float(gridSize - 1)
                let index = Float(row * gridSize + col)
                let isEdgeX = col == 0 || col == gridSize - 1
                let isEdgeY = row == 0 || row == gridSize - 1

                // each point gets its own speed and phase so the motion never lines up
                let speedA = 0.11 + 0.017 * index.truncatingRemainder(dividingBy: 5)
                let speedB = 0.09 + 0.013 * index.truncatingRemainder(dividingBy: 7)
                let phase = index * 1.7

                var x = baseX
                var y = baseY
                if !isEdgeX { x += 0.16 * sin(t * speedA + phase) }
                if !isEdgeY { y += 0.16 * cos(t * speedB + phase * 0.8) }
                // edge points move only along the edge, so the mesh always covers the screen
                if isEdgeX && !isEdgeY { y += 0.08 * sin(t * speedB + phase) }
                if isEdgeY && !isEdgeX { x += 0.08 * cos(t * speedA + phase) }

                result.append(SIMD2(min(1, max(0, x)), min(1, max(0, y))))
            }
        }
        return result
    }

    /// spreads the palette over the 16 grid points in a stable, per-album pattern.
    /// the most common colour gets the most points, so it reads as the background.
    private static func gridColors(from palette: [Color], seed: UInt64) -> [Color] {
        let colors = palette.isEmpty ? ArtworkPalette.fallback : palette
        let pattern = [0, 1, 0, 2,
                       3, 0, 4, 1,
                       2, 5, 0, 3,
                       0, 1, 2, 0]
        let count = colors.count
        // rotate the accent colours per album so different songs don't look identical
        let offset = Int(seed % 5)
        return pattern.map { slot in
            guard count > 1, slot != 0 else { return colors[0] }
            return colors[1 + (slot - 1 + offset) % (count - 1)]
        }
    }

    // MARK: palette

    private func updatePalette() {
        activeID = imageID
        if let id = imageID, let cached = Self.cache[id] {
            withAnimation(.easeInOut(duration: 1.2)) { palette = cached }
            return
        }
        guard let image = image else {
            withAnimation(.easeInOut(duration: 1.2)) { palette = ArtworkPalette.fallback }
            return
        }
        let id = imageID
        DispatchQueue.global(qos: .userInitiated).async {
            let colors = ArtworkPalette.colors(from: image)
            DispatchQueue.main.async {
                if let id = id {
                    if Self.cache.count > 200 { Self.cache.removeAll() }
                    Self.cache[id] = colors
                }
                // the song changed while we were working
                guard id == activeID else { return }
                withAnimation(.easeInOut(duration: 1.2)) {
                    palette = colors
                }
            }
        }
    }
}
