//
//  SettingsView.swift
//  Jukebox
//
//  settings screen with last.fm integration
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var lastFM = LastFMManager.shared
    @ObservedObject var sleepTimer = SleepTimerManager.shared
    
    @State private var user = ""
    @State private var pass = ""
    @State private var loading = false
    @State private var error: String?
    @State private var sleepAtTime = Date().addingTimeInterval(60 * 60)
    
    // crossfade settings
    @AppStorage("crossfadeEnabled") private var crossfadeEnabled = false
    @AppStorage("crossfadeDuration") private var crossfadeDuration = 6.0
    
    // appearance
    @AppStorage("appTheme") private var appTheme = 0 // 0 = system, 1 = light, 2 = dark
    
    // computed color scheme for this view
    private var colorScheme: ColorScheme? {
        switch appTheme {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
    
    // cache management
    @State private var showClearCacheAlert = false
    @State private var imageCacheSize: Int64 = 0
    @State private var lyricsCacheSize: Int64 = 0
    
    var body: some View {
        NavigationView {
            List {
                // last.fm section
                Section("Last.fm") {
                    if lastFM.isLoggedIn {
                        loggedInView
                    } else {
                        loginFormView
                    }
                }
                
                Section("Playback") {
                    Toggle("Crossfade", isOn: $crossfadeEnabled)
                    
                    if crossfadeEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Crossfade Duration: \(Int(crossfadeDuration))s")
                                .font(.subheadline)
                            Slider(value: $crossfadeDuration, in: 1...12, step: 1)
                        }
                    }
                }
                
                Section("Sleep Timer") {
                    sleepTimerSection
                }
                
                Section("Storage") {
                    storageSection
                }
                
                Section("Appearance") {
                    Picker(selection: Binding(
                        get: { appTheme },
                        set: { newValue in
                            withAnimation(.easeInOut(duration: 0.3)) {
                                appTheme = newValue
                            }
                        }
                    )) {
                        Label("System", systemImage: "iphone").tag(0)
                        Label("Light", systemImage: "sun.max.fill").tag(1)
                        Label("Dark", systemImage: "moon.fill").tag(2)
                    } label: {
                        Text("Theme")
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                refreshCacheSizes()
            }
            .alert("Clear Cache", isPresented: $showClearCacheAlert) {
                Button("Images", role: .destructive) {
                    ArtistImageManager.shared.clearCache()
                    refreshCacheSizes()
                }
                Button("Lyrics", role: .destructive) {
                    LyricsManager.shared.clearCache()
                    refreshCacheSizes()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Which cache would you like to clear?")
            }
            .preferredColorScheme(colorScheme)
            .animation(.easeInOut(duration: 0.3), value: appTheme)
        }
    }
    
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
    
    // MARK: - logged in view
    
    private var loggedInView: some View {
        Group {
            HStack {
                Text("Signed in as")
                Spacer()
                Text(lastFM.username).foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Scrobble at \(Int(lastFM.scrobblePercent * 100))%")
                    .font(.subheadline)
                Slider(value: $lastFM.scrobblePercent, in: 0.1...1.0, step: 0.1)
                    .onChange(of: lastFM.scrobblePercent) { _ in
                        lastFM.savePercent()
                    }
            }
            
            Button("Sign Out", role: .destructive) {
                lastFM.logout()
            }
        }
    }
    
    // MARK: - login form
    
    @ViewBuilder
    private var loginFormView: some View {
        if !lastFM.isConfigured {
            Text("Last.fm isn't available in this build because it was built without a Last.fm API key.")
                .font(.footnote)
                .foregroundColor(.secondary)
        } else {
            loginFields
        }
    }
    
    private var loginFields: some View {
        Group {
            TextField("Username", text: $user)
                .disableAutocorrection(true)
                .autocapitalization(.none)
            
            SecureField("Password", text: $pass)
            
            if let error = error {
                Text(error).foregroundColor(.red).font(.caption)
            }
            
            Button(action: doLogin) {
                if loading {
                    ProgressView()
                } else {
                    Text("Log In")
                }
            }
            .disabled(user.isEmpty || pass.isEmpty || loading)
        }
    }
    
    // MARK: - actions
    
    private func doLogin() {
        loading = true
        error = nil
        
        lastFM.login(user: user, pass: pass) { success, err in
            loading = false
            if success {
                pass = ""
            } else {
                error = err ?? "Login failed"
            }
        }
    }
    
    // MARK: - sleep timer section
    
    private var sleepTimerSection: some View {
        Group {
            if sleepTimer.isActive {
                HStack {
                    Image(systemName: "moon.fill")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sleepTimer.timerType.displayName)
                            .font(.system(size: 16, weight: .medium))
                        Text(sleepTimer.shortDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Cancel") {
                        sleepTimer.stopTimer()
                    }
                    .foregroundColor(.red)
                }
            } else {
                Button(action: { sleepTimer.startTimer(type: .afterOneSong) }) {
                    HStack {
                        Image(systemName: "music.note")
                        Text("After 1 Song")
                        Spacer()
                    }
                }
                
                Button(action: { sleepTimer.startTimer(type: .fifteenMinutes) }) {
                    HStack {
                        Image(systemName: "timer")
                        Text("15 Minutes")
                        Spacer()
                    }
                }
                
                Button(action: { sleepTimer.startTimer(type: .thirtyMinutes) }) {
                    HStack {
                        Image(systemName: "timer")
                        Text("30 Minutes")
                        Spacer()
                    }
                }
                
                Button(action: { sleepTimer.startTimer(type: .oneHour) }) {
                    HStack {
                        Image(systemName: "timer")
                        Text("1 Hour")
                        Spacer()
                    }
                }
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.accentColor)
                    DatePicker("At", selection: $sleepAtTime, displayedComponents: .hourAndMinute)
                    Button("Start") {
                        sleepTimer.startTimer(type: .atSpecificTime, specificTime: sleepAtTime)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
    
    // MARK: - storage section
    
    private var storageSection: some View {
        Group {
            HStack {
                Text("Image Cache")
                Spacer()
                Text(formatBytes(imageCacheSize))
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Lyrics Cache")
                Spacer()
                Text(formatBytes(lyricsCacheSize))
                    .foregroundColor(.secondary)
            }
            
            Button(action: {
                showClearCacheAlert = true
            }) {
                HStack {
                    Image(systemName: "trash")
                    Text("Clear Cache")
                }
            }
            .foregroundColor(.red)
        }
    }
    
    // MARK: - helpers
    
    private func refreshCacheSizes() {
        imageCacheSize = ArtistImageManager.shared.cacheSize()
        lyricsCacheSize = LyricsManager.shared.cacheSize()
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

