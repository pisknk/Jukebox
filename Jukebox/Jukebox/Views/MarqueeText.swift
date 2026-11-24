//
//  MarqueeText.swift
//  Jukebox
//
//  Single-line text that scrolls to show the whole thing when it doesn't fit
//  (like song titles in the Music app). Used by the Native Glass mini player.
//

import SwiftUI

@available(iOS 26, *)
struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var color: Color = .primary
    /// space between the end of the text and the start of its repeat
    var gap: CGFloat = 36
    /// scrolling speed in points per second
    var speed: CGFloat = 32
    /// pause at the start before each scroll
    var pause: Double = 2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isScrolling = false

    private var overflows: Bool { textWidth > containerWidth + 0.5 }
    private var shouldScroll: Bool { overflows && !reduceMotion }

    var body: some View {
        // an invisible copy sets the height and takes the available width
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                if shouldScroll {
                    // two copies side by side: when the first has scrolled away,
                    // the second sits exactly where it started, so the loop is seamless
                    HStack(spacing: gap) {
                        label
                        label
                    }
                    .fixedSize()
                    .offset(x: offset)
                } else {
                    // fits, or Reduce Motion is on: plain text (truncates if needed)
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
            }
            .clipped()
            .mask(edgeFade)
            .background(
                // measure the full text width without letting it affect layout
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
            // restart whenever the text or the space for it changes
            .task(id: "\(text)|\(Int(textWidth))|\(Int(containerWidth))|\(reduceMotion)") {
                await scrollLoop()
            }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
    }

    /// soft edges only while the text is cut off
    @ViewBuilder
    private var edgeFade: some View {
        if shouldScroll {
            LinearGradient(
                stops: [
                    .init(color: isScrolling ? .clear : .black, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Rectangle()
        }
    }

    private func scrollLoop() async {
        resetToStart()
        guard shouldScroll else { return }

        let distance = textWidth + gap
        let duration = Double(distance / speed)

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(pause))
            guard !Task.isCancelled else { return }

            isScrolling = true
            withAnimation(.linear(duration: duration)) {
                offset = -distance
            }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }

            resetToStart()
        }
    }

    /// jump back to the start without animating (the second copy is already there)
    private func resetToStart() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            offset = 0
            isScrolling = false
        }
    }
}
