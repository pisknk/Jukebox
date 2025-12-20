//
//  JukeboxApp.swift
//  Jukebox
//
//  Created on 2025-12-15.
//

import SwiftUI

@main
struct JukeboxApp: App {
    @AppStorage("appTheme") private var appTheme = 0 // 0 = system, 1 = light, 2 = dark
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(MusicPlayerManager.shared)
                .preferredColorScheme(colorScheme)
        }
    }
    
    private var colorScheme: ColorScheme? {
        switch appTheme {
        case 1: return .light
        case 2: return .dark
        default: return nil // system
        }
    }
}
