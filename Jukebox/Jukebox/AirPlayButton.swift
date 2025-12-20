//
//  AirPlayButton.swift
//  Jukebox
//
//  uiviewrepresentable wrapper for avroutepickerview to enable airplay
//

import SwiftUI
import AVKit

struct AirPlayButton: UIViewRepresentable {
    var tintColor: UIColor = .white
    
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = tintColor
        routePickerView.activeTintColor = .systemBlue
        routePickerView.prioritizesVideoDevices = false
        return routePickerView
    }
    
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
    }
}
