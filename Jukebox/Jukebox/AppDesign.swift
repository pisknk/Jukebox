//
//  AppDesign.swift
//  Jukebox
//
//  Which design language the app uses. Chosen once at launch: changing it in
//  Settings takes effect the next time the app starts.
//

import SwiftUI

enum DesignLanguage: String, CaseIterable, Identifiable {
    /// the original custom design (custom tab bar, header and search bars)
    case amity = "amity"
    /// native iOS 26 Liquid Glass (system tab bar, navigation bars, search)
    case nativeGlass = "nativeGlass"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .amity: return "Amity 1.0"
        case .nativeGlass: return "Native Glass"
        }
    }

    /// Native Glass needs iOS 26
    static var isNativeGlassSupported: Bool {
        if #available(iOS 26, *) { return true }
        return false
    }

    /// what a fresh install uses
    static var defaultValue: DesignLanguage {
        isNativeGlassSupported ? .nativeGlass : .amity
    }
}

enum AppDesign {
    /// UserDefaults key for the chosen design (also settable with the launch argument `-designLanguage amity`)
    static let storageKey = "designLanguage"

    /// the design in use for this launch. read once, so changing the setting needs a restart.
    static let current: DesignLanguage = {
        let stored = UserDefaults.standard.string(forKey: storageKey).flatMap(DesignLanguage.init(rawValue:))
        let chosen = stored ?? DesignLanguage.defaultValue
        // Native Glass on an older iOS falls back to Amity
        if chosen == .nativeGlass && !DesignLanguage.isNativeGlassSupported {
            return .amity
        }
        return chosen
    }()

    static var isNativeGlass: Bool { current == .nativeGlass }

    /// empty space at the end of lists so the last rows can scroll above the custom
    /// tab bar and mini player. the native tab bar handles this itself.
    static func legacyBottomSpace(_ height: CGFloat) -> CGFloat {
        isNativeGlass ? 0 : height
    }
}

// MARK: - Adaptive modifiers

extension View {
    /// native search field in Native Glass; Amity draws its own `SearchBar` instead
    func adaptiveSearchable(text: Binding<String>, prompt: String) -> some View {
        modifier(AdaptiveSearchable(text: text, prompt: prompt))
    }

    /// Liquid Glass behind a control in Native Glass; unchanged in Amity
    func adaptiveGlass<S: Shape>(in shape: S, interactive: Bool = true) -> some View {
        modifier(AdaptiveGlass(shape: shape, interactive: interactive))
    }
}

private struct AdaptiveSearchable: ViewModifier {
    @Binding var text: String
    let prompt: String

    func body(content: Content) -> some View {
        if AppDesign.isNativeGlass {
            content.searchable(text: $text, prompt: prompt)
        } else {
            content
        }
    }
}

private struct AdaptiveGlass<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26, *), AppDesign.isNativeGlass {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
        }
    }
}
