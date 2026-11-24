//
//  LastFMManager.swift
//  Jukebox
//
//  last.fm scrobbling. scrobbles are queued on disk and sent in batches, so plays made
//  offline are sent later. all state is only touched on the main thread.
//
//  the api key and secret come from Info.plist, which gets them from the build settings
//  LASTFM_API_KEY / LASTFM_API_SECRET (see Config/Secrets.example.xcconfig). they are not
//  stored in the repository.
//

import Foundation
import MediaPlayer

final class LastFMManager: ObservableObject {
    static let shared = LastFMManager()

    // api config
    private let apiKey: String
    private let apiSecret: String
    private let apiURL = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    /// false when the app was built without last.fm keys
    var isConfigured: Bool { !apiKey.isEmpty && !apiSecret.isEmpty }

    // published state
    @Published private(set) var isLoggedIn = false
    @Published private(set) var username: String = ""
    @Published var scrobblePercent: Double = 0.4

    // private
    private var sessionKey: String = ""
    private let sessionKeychainAccount = "lastfm.session"

    private var pendingScrobbles: [PendingScrobble] = []
    private var isSendingScrobbles = false
    private let pendingFile: URL
    private let maxPendingScrobbles = 1000
    private let maxScrobbleAge: TimeInterval = 14 * 24 * 60 * 60  // last.fm ignores older ones

    private init() {
        apiKey = Self.infoValue("LastFMAPIKey")
        apiSecret = Self.infoValue("LastFMAPISecret")

        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        pendingFile = support.appendingPathComponent("pending_scrobbles.json")

        loadSession()
        loadPendingScrobbles()
        sendPendingScrobbles()
    }

    /// reads a build-time value from Info.plist; empty if it wasn't set
    private static func infoValue(_ key: String) -> String {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("$(") ? "" : value
    }

    // MARK: - persistence

    private func loadSession() {
        // move the session key out of UserDefaults (plain text) into the keychain
        if let legacy = UserDefaults.standard.string(forKey: "lfm_sk"), !legacy.isEmpty {
            KeychainStore.set(legacy, for: sessionKeychainAccount)
            UserDefaults.standard.removeObject(forKey: "lfm_sk")
        }
        sessionKey = KeychainStore.string(for: sessionKeychainAccount) ?? ""
        username = UserDefaults.standard.string(forKey: "lfm_user") ?? ""
        scrobblePercent = UserDefaults.standard.double(forKey: "lfm_pct")
        if scrobblePercent <= 0 { scrobblePercent = 0.4 }
        isLoggedIn = !sessionKey.isEmpty
    }

    func savePercent() {
        UserDefaults.standard.set(scrobblePercent, forKey: "lfm_pct")
    }

    private func loadPendingScrobbles() {
        guard let data = try? Data(contentsOf: pendingFile),
              let saved = try? JSONDecoder().decode([PendingScrobble].self, from: data) else { return }
        pendingScrobbles = saved
    }

    private func savePendingScrobbles() {
        let snapshot = pendingScrobbles
        let file = pendingFile
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    // MARK: - auth

    func login(user: String, pass: String, completion: @escaping (Bool, String?) -> Void) {
        guard isConfigured else {
            completion(false, "Last.fm isn't set up in this build (missing API key).")
            return
        }

        let params: [String: String] = [
            "method": "auth.getMobileSession",
            "username": user,
            "password": pass,
            "api_key": apiKey
        ]

        post(params) { [weak self] json, error in
            guard let self = self else { return }
            if let error = error {
                completion(false, error)
                return
            }
            guard let session = json?["session"] as? [String: Any],
                  let key = session["key"] as? String,
                  let name = session["name"] as? String else {
                completion(false, "Missing session data")
                return
            }

            self.sessionKey = key
            self.username = name
            self.isLoggedIn = true
            KeychainStore.set(key, for: self.sessionKeychainAccount)
            UserDefaults.standard.set(name, forKey: "lfm_user")
            self.savePercent()
            self.sendPendingScrobbles()
            completion(true, nil)
        }
    }

    func logout() {
        sessionKey = ""
        username = ""
        isLoggedIn = false
        KeychainStore.delete(sessionKeychainAccount)
        UserDefaults.standard.removeObject(forKey: "lfm_user")
    }

    // MARK: - scrobbling

    func nowPlaying(_ song: MPMediaItem) {
        guard isConfigured, isLoggedIn, let artist = song.artist, let track = song.title else { return }

        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "artist": artist,
            "track": track,
            "api_key": apiKey,
            "sk": sessionKey
        ]
        if let album = song.albumTitle { params["album"] = album }
        if song.playbackDuration > 0 { params["duration"] = String(Int(song.playbackDuration)) }

        post(params) { _, _ in }
    }

    /// `startedAt` is when the song started playing, which is what last.fm expects
    func scrobble(_ song: MPMediaItem, startedAt: Date) {
        guard isConfigured, isLoggedIn, let artist = song.artist, let track = song.title else { return }

        pendingScrobbles.append(PendingScrobble(
            artist: artist,
            track: track,
            album: song.albumTitle,
            duration: song.playbackDuration > 0 ? Int(song.playbackDuration) : nil,
            timestamp: Int(startedAt.timeIntervalSince1970)
        ))
        if pendingScrobbles.count > maxPendingScrobbles {
            pendingScrobbles.removeFirst(pendingScrobbles.count - maxPendingScrobbles)
        }
        savePendingScrobbles()
        sendPendingScrobbles()
    }

    /// sends queued scrobbles, up to 50 per request
    private func sendPendingScrobbles() {
        guard isConfigured, isLoggedIn, !isSendingScrobbles else { return }

        let cutoff = Int(Date().timeIntervalSince1970 - maxScrobbleAge)
        pendingScrobbles.removeAll { $0.timestamp < cutoff }
        guard !pendingScrobbles.isEmpty else { return }

        let batch = Array(pendingScrobbles.prefix(50))
        var params = PendingScrobble.batchParameters(batch)
        params["method"] = "track.scrobble"
        params["api_key"] = apiKey
        params["sk"] = sessionKey

        isSendingScrobbles = true
        postWithCode(params) { [weak self] _, error, code in
            guard let self = self else { return }
            self.isSendingScrobbles = false

            let sent = error == nil
            // 11/16: service temporarily unavailable, 29: rate limited -> keep and retry later
            let retryLater = code == 11 || code == 16 || code == 29 || (error != nil && code == nil)

            if code == 9 {
                // invalid session key: sign out, keep the scrobbles for after signing in again
                self.logout()
                return
            }
            if sent || !retryLater {
                // sent, or rejected for good (e.g. bad data) - don't block the queue on it
                self.pendingScrobbles.removeFirst(min(batch.count, self.pendingScrobbles.count))
                self.savePendingScrobbles()
                if sent && !self.pendingScrobbles.isEmpty {
                    self.sendPendingScrobbles()
                }
            }
        }
    }

    // MARK: - network

    /// signs and posts; completion on main with (json, error message)
    private func post(_ params: [String: String], completion: @escaping ([String: Any]?, String?) -> Void) {
        postWithCode(params) { json, error, _ in completion(json, error) }
    }

    /// signs and posts; completion on main with (json, error message, last.fm error code)
    private func postWithCode(_ params: [String: String], completion: @escaping ([String: Any]?, String?, Int?) -> Void) {
        var signed = params
        signed["api_sig"] = LastFMSignature.sign(params, secret: apiSecret)
        signed["format"] = "json"

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.query(signed).data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, _, error in
            var json: [String: Any]? = nil
            var message: String? = nil
            var code: Int? = nil

            if let error = error {
                message = error.localizedDescription
            } else if let data = data,
                      let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                json = parsed
                if let errorCode = parsed["error"] as? Int {
                    code = errorCode
                    message = "Error \(errorCode): \(parsed["message"] as? String ?? "Unknown error")"
                }
            } else {
                message = "Unexpected response from Last.fm"
            }

            DispatchQueue.main.async { completion(json, message, code) }
        }.resume()
    }
}
