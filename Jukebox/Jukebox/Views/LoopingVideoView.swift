//
//  LoopingVideoView.swift
//  Jukebox
//
//  Plays a local video muted and on loop, filling its frame. Used for the
//  animated album cover at the top of Now Playing (Native Glass).
//

import SwiftUI
import AVFoundation

struct LoopingVideoView: UIViewRepresentable {
    let url: URL
    /// follows the music: the cover only moves while a song plays
    var isPlaying: Bool

    func makeUIView(context: Context) -> LoopingPlayerView {
        let view = LoopingPlayerView()
        view.load(url)
        view.setPlaying(isPlaying)
        return view
    }

    func updateUIView(_ view: LoopingPlayerView, context: Context) {
        if view.url != url {
            view.load(url)
        }
        view.setPlaying(isPlaying)
    }

    static func dismantleUIView(_ view: LoopingPlayerView, coordinator: ()) {
        view.stop()
    }
}

final class LoopingPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private(set) var url: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // silent, and never takes over the music's audio or keeps the screen awake
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.audiovisualBackgroundPlaybackPolicy = .pauses
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func load(_ url: URL) {
        self.url = url
        player.removeAllItems()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
    }

    func setPlaying(_ playing: Bool) {
        if playing {
            if player.timeControlStatus != .playing { player.play() }
        } else {
            player.pause()
        }
    }

    func stop() {
        player.pause()
        looper = nil
        player.removeAllItems()
    }
}
