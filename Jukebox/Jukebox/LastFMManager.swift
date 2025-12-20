//
//  LastFMManager.swift
//  Jukebox
//
//  simple last.fm scrobbling manager
//

import Foundation
import CryptoKit
import MediaPlayer

final class LastFMManager: ObservableObject {
    static let shared = LastFMManager()
    
    // api config
    private let apiKey = "3fca4c72bbd01a009d42e5a90c1ab822"
    private let apiSecret = "3b1539bf973546d4c3278366409714cd"
    private let apiURL = "https://ws.audioscrobbler.com/2.0/"
    
    // published state
    @Published var isLoggedIn = false
    @Published var username: String = ""
    @Published var scrobblePercent: Double = 0.4
    
    // private
    private var sessionKey: String = ""
    
    private init() {
        loadSession()
    }
    
    // MARK: - persistence
    
    private func loadSession() {
        sessionKey = UserDefaults.standard.string(forKey: "lfm_sk") ?? ""
        username = UserDefaults.standard.string(forKey: "lfm_user") ?? ""
        scrobblePercent = UserDefaults.standard.double(forKey: "lfm_pct")
        if scrobblePercent == 0 { scrobblePercent = 0.4 }
        isLoggedIn = !sessionKey.isEmpty
    }
    
    private func saveSession() {
        UserDefaults.standard.set(sessionKey, forKey: "lfm_sk")
        UserDefaults.standard.set(username, forKey: "lfm_user")
        UserDefaults.standard.set(scrobblePercent, forKey: "lfm_pct")
    }
    
    func savePercent() {
        UserDefaults.standard.set(scrobblePercent, forKey: "lfm_pct")
    }
    
    // MARK: - auth
    
    func login(user: String, pass: String, completion: @escaping (Bool, String?) -> Void) {
        var params: [String: String] = [
            "method": "auth.getMobileSession",
            "username": user,
            "password": pass,
            "api_key": apiKey
        ]
        params["api_sig"] = sign(params)
        params["format"] = "json"
        
        post(params) { [weak self] data, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async { completion(false, error) }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async { completion(false, "No data received") }
                return
            }
            
            // debug: print raw response
            if let rawResponse = String(data: data, encoding: .utf8) {
                print("Last.fm response: \(rawResponse)")
            }
            
            // parse json
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(false, "Failed to parse JSON") }
                return
            }
            
            // check for error in response
            if let errorCode = json["error"] as? Int, let message = json["message"] as? String {
                DispatchQueue.main.async { completion(false, "Error \(errorCode): \(message)") }
                return
            }
            
            // extract session
            guard let session = json["session"] as? [String: Any],
                  let key = session["key"] as? String,
                  let name = session["name"] as? String else {
                DispatchQueue.main.async { completion(false, "Missing session data") }
                return
            }
            
            DispatchQueue.main.async {
                self.sessionKey = key
                self.username = name
                self.isLoggedIn = true
                self.saveSession()
                completion(true, nil)
            }
        }
    }
    
    func logout() {
        sessionKey = ""
        username = ""
        isLoggedIn = false
        UserDefaults.standard.removeObject(forKey: "lfm_sk")
        UserDefaults.standard.removeObject(forKey: "lfm_user")
    }
    
    // MARK: - scrobbling
    
    func nowPlaying(_ song: MPMediaItem) {
        guard isLoggedIn, let artist = song.artist, let track = song.title else { return }
        
        var params: [String: String] = [
            "method": "track.updateNowPlaying",
            "artist": artist,
            "track": track,
            "api_key": apiKey,
            "sk": sessionKey
        ]
        if let album = song.albumTitle { params["album"] = album }
        params["api_sig"] = sign(params)
        params["format"] = "json"
        
        post(params) { _, _ in }
    }
    
    func scrobble(_ song: MPMediaItem) {
        guard isLoggedIn, let artist = song.artist, let track = song.title else { return }
        
        var params: [String: String] = [
            "method": "track.scrobble",
            "artist": artist,
            "track": track,
            "timestamp": "\(Int(Date().timeIntervalSince1970))",
            "api_key": apiKey,
            "sk": sessionKey
        ]
        if let album = song.albumTitle { params["album"] = album }
        params["api_sig"] = sign(params)
        params["format"] = "json"
        
        post(params) { _, _ in
            print("scrobbled: \(track)")
        }
    }
    
    // MARK: - artist info
    
    func getArtistImage(name: String, completion: @escaping (URL?) -> Void) {
        // build url for GET request (no auth needed for artist.getinfo)
        var components = URLComponents(string: apiURL)!
        components.queryItems = [
            URLQueryItem(name: "method", value: "artist.getinfo"),
            URLQueryItem(name: "artist", value: name),
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "format", value: "json")
        ]
        
        guard let url = components.url else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let artist = json["artist"] as? [String: Any],
                  let images = artist["image"] as? [[String: Any]] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // find the largest image (extralarge or mega)
            var imageURL: URL?
            for image in images.reversed() {
                if let size = image["size"] as? String,
                   let urlStr = image["#text"] as? String,
                   !urlStr.isEmpty,
                   (size == "extralarge" || size == "mega" || size == "large") {
                    imageURL = URL(string: urlStr)
                    break
                }
            }
            
            DispatchQueue.main.async { completion(imageURL) }
        }.resume()
    }
    
    // MARK: - network
    
    private func post(_ params: [String: String], completion: @escaping (Data?, String?) -> Void) {
        guard let url = URL(string: apiURL) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(nil, error.localizedDescription)
                return
            }
            completion(data, nil)
        }.resume()
    }
    
    // MARK: - signature
    
    private func sign(_ params: [String: String]) -> String {
        var str = ""
        for key in params.keys.sorted() {
            if key != "format" && key != "callback" {
                str += key + (params[key] ?? "")
            }
        }
        str += apiSecret
        
        let digest = Insecure.MD5.hash(data: Data(str.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
