//
//  LyricsManager.swift
//  Jukebox
//
//  fetches synced lyrics from lrclib.net api with a size-limited cache on disk.
//  all state is only touched on the main thread.
//

import Foundation

final class LyricsManager {
    static let shared = LyricsManager()

    private let baseURL = "https://lrclib.net/api"
    private let maxCachedSongs = 500

    private var cache: [String: [LyricLine]] = [:]
    private var cacheOrder: [String] = []        // oldest first, for trimming
    private var knownMissing: Set<String> = []   // songs lrclib has no synced lyrics for (this session)

    private let cacheFile: URL
    private let ioQueue = DispatchQueue(label: "jukebox.lyrics.cache", qos: .utility)
    private let legacyDefaultsKey = "com.jukebox.lyrics.cache"

    private struct StoredCache: Codable {
        var entries: [String: [LyricLine]]
        var order: [String]
    }

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheFile = caches.appendingPathComponent("lyrics_cache.json")

        // the old cache lived in UserDefaults and was parsed by the old parser; drop it
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)

        if let data = try? Data(contentsOf: cacheFile),
           let stored = try? JSONDecoder().decode(StoredCache.self, from: data) {
            cache = stored.entries
            cacheOrder = stored.order.filter { stored.entries[$0] != nil }
        }
    }

    // MARK: - fetch lyrics

    /// call on the main thread; completion runs on the main thread
    func getLyrics(track: String, artist: String, completion: @escaping ([LyricLine]?) -> Void) {
        let key = "\(artist)-\(track)".lowercased()
        if let cached = cache[key] {
            completion(cached)
            return
        }
        if knownMissing.contains(key) {
            completion(nil)
            return
        }

        var components = URLComponents(string: "\(baseURL)/get")!
        components.percentEncodedQuery = FormEncoding.query([
            "track_name": track,
            "artist_name": artist
        ])
        guard let url = components.url else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Jukebox/1.0 (iOS music player)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode
            var lines: [LyricLine]? = nil
            if error == nil, let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let synced = json["syncedLyrics"] as? String, !synced.isEmpty {
                // only synced lyrics: plain lyrics have no timestamps
                let parsed = LRCParser.parse(synced)
                lines = parsed.isEmpty ? nil : parsed
            }
            // only remember "no lyrics" for a real answer, not a network failure
            let definitelyMissing = error == nil && (status == 404 || (status == 200 && lines == nil))

            DispatchQueue.main.async {
                guard let self = self else { return }
                if let lines = lines {
                    self.store(lines, for: key)
                } else if definitelyMissing {
                    self.knownMissing.insert(key)
                }
                completion(lines)
            }
        }.resume()
    }

    // MARK: - cache

    private func store(_ lines: [LyricLine], for key: String) {
        cache[key] = lines
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > maxCachedSongs {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
        save()
    }

    private func save() {
        let snapshot = StoredCache(entries: cache, order: cacheOrder)
        let file = cacheFile
        ioQueue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: - find current line index

    func currentLineIndex(for time: TimeInterval, in lyrics: [LyricLine]) -> Int? {
        LRCParser.lineIndex(at: time, in: lyrics)
    }

    // MARK: - clear cache

    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
        knownMissing.removeAll()
        let file = cacheFile
        ioQueue.async {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - cache size

    func cacheSize() -> Int64 {
        // wait for pending writes so the number is current
        ioQueue.sync {}
        let attributes = try? FileManager.default.attributesOfItem(atPath: cacheFile.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}
