//
//  LyricsManager.swift
//  Jukebox
//
//  fetches synced lyrics from lrclib.net api with persistent caching
//

import Foundation

// MARK: - lyric line model
struct LyricLine: Identifiable, Codable {
    let id: UUID
    let time: TimeInterval  // time in seconds
    let text: String
    
    init(id: UUID = UUID(), time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

final class LyricsManager {
    static let shared = LyricsManager()
    
    private let baseURL = "https://lrclib.net/api"
    private var memoryCache: [String: [LyricLine]] = [:]
    private let cacheKey = "com.jukebox.lyrics.cache"
    
    private init() {
        loadPersistentCache()
    }
    
    // MARK: - persistent cache
    
    private func loadPersistentCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let decoded = try? JSONDecoder().decode([String: [LyricLine]].self, from: data) else {
            return
        }
        memoryCache = decoded
    }
    
    private func savePersistentCache() {
        guard let encoded = try? JSONEncoder().encode(memoryCache) else { return }
        UserDefaults.standard.set(encoded, forKey: cacheKey)
    }
    
    // MARK: - fetch lyrics
    
    func getLyrics(track: String, artist: String, completion: @escaping ([LyricLine]?) -> Void) {
        // check cache first
        let cacheKey = "\(artist)-\(track)".lowercased()
        if let cached = memoryCache[cacheKey] {
            completion(cached)
            return
        }
        
        // build url
        var components = URLComponents(string: "\(baseURL)/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        
        guard let url = components.url else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Jukebox/1.0", forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self,
                  let data = data,
                  error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // parse response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // only use synced lyrics (ignore plain lyrics as they lack timestamps)
            var lyrics: [LyricLine]?
            
            if let syncedLyrics = json["syncedLyrics"] as? String, !syncedLyrics.isEmpty {
                lyrics = self.parseLRC(syncedLyrics)
            }
            
            // cache result persistently
            if let lyrics = lyrics {
                self.memoryCache[cacheKey] = lyrics
                self.savePersistentCache()
            }
            
            DispatchQueue.main.async { completion(lyrics) }
        }.resume()
    }
    
    // MARK: - parse lrc format
    
    private func parseLRC(_ lrc: String) -> [LyricLine] {
        var lines: [LyricLine] = []
        
        // regex: [mm:ss.xx] or [mm:ss]
        let pattern = #"\[(\d+):(\d+)(?:\.(\d+))?\]\s*(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        
        for line in lrc.components(separatedBy: "\n") {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, range: range) {
                let minutes = Int((line as NSString).substring(with: match.range(at: 1))) ?? 0
                let seconds = Int((line as NSString).substring(with: match.range(at: 2))) ?? 0
                var milliseconds = 0
                if match.range(at: 3).location != NSNotFound {
                    let msStr = (line as NSString).substring(with: match.range(at: 3))
                    milliseconds = Int(msStr) ?? 0
                    // handle different precision (2 or 3 digits)
                    if msStr.count == 2 { milliseconds *= 10 }
                }
                
                let text = (line as NSString).substring(with: match.range(at: 4))
                let time = TimeInterval(minutes * 60 + seconds) + TimeInterval(milliseconds) / 1000.0
                
                if !text.isEmpty {
                    lines.append(LyricLine(time: time, text: text))
                }
            }
        }
        
        return lines.sorted { $0.time < $1.time }
    }
    
    // MARK: - find current line index
    
    func currentLineIndex(for time: TimeInterval, in lyrics: [LyricLine]) -> Int? {
        guard !lyrics.isEmpty else { return nil }
        
        // find the last line that has started
        var index: Int? = nil
        for (i, line) in lyrics.enumerated() {
            if line.time <= time {
                index = i
            } else {
                break
            }
        }
        return index
    }
    
    // MARK: - clear cache (optional utility)
    
    func clearCache() {
        memoryCache.removeAll()
        UserDefaults.standard.removeObject(forKey: cacheKey)
    }
    
    // MARK: - cache size
    
    func cacheSize() -> Int64 {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return 0 }
        return Int64(data.count)
    }
}
