//
//  ArtistImageManager.swift
//  Jukebox
//
//  fetches artist images from musicbrainz + wikimedia commons.
//  all state is only touched on the main thread; completions run on the main thread.
//

import Foundation
import UIKit

final class ArtistImageManager {
    static let shared = ArtistImageManager()

    private let userAgent = "Jukebox/1.0 (iOS music player)"
    private let cacheDirectory: URL
    private let indexFile: URL

    /// artist -> cached image file name (relative, so it survives app updates moving the container)
    private var imageFiles: [String: String] = [:]
    /// artists we looked up and found no image for, and when; retried after a week
    private var misses: [String: Date] = [:]
    private let missRetryInterval: TimeInterval = 7 * 24 * 60 * 60

    /// lookups in progress: everyone asking for the same artist shares one lookup
    private var pending: [String: [(URL?) -> Void]] = [:]

    /// musicbrainz allows one request per second per client
    private var nextMusicBrainzSlot = Date.distantPast
    private let musicBrainzSpacing: TimeInterval = 1.1

    private struct StoredIndex: Codable {
        var files: [String: String]
        var misses: [String: Date]
    }

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = caches.appendingPathComponent("ArtistImages", isDirectory: true)
        indexFile = cacheDirectory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // the old url_cache.json stored absolute paths that break after app updates; start fresh
        try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("url_cache.json"))

        if let data = try? Data(contentsOf: indexFile),
           let stored = try? JSONDecoder().decode(StoredIndex.self, from: data) {
            imageFiles = stored.files
            misses = stored.misses
        }
    }

    // MARK: - public api

    /// call on the main thread
    func getArtistImage(name: String, completion: @escaping (URL?) -> Void) {
        let key = ArtistImageNaming.normalizedName(name)
        guard !key.isEmpty else {
            completion(nil)
            return
        }

        // cached on disk (iOS may have purged the file; then look it up again)
        if let fileName = imageFiles[key] {
            let url = cacheDirectory.appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                completion(url)
                return
            }
            imageFiles.removeValue(forKey: key)
        }

        // looked up recently and found nothing
        if let missDate = misses[key], Date().timeIntervalSince(missDate) < missRetryInterval {
            completion(nil)
            return
        }

        // already being looked up
        if pending[key] != nil {
            pending[key]?.append(completion)
            return
        }
        pending[key] = [completion]

        lookUp(name: name) { [weak self] result in
            self?.finish(key: key, name: name, result: result)
        }
    }

    // MARK: - lookup pipeline

    private enum LookupResult {
        case found(URL)    // remote image url
        case notFound      // the services answered: no image
        case failed        // network problem; don't remember
    }

    private func finish(key: String, name: String, result: LookupResult) {
        switch result {
        case .found(let remoteURL):
            download(remoteURL, for: name) { [weak self] localURL in
                guard let self = self else { return }
                if let localURL = localURL {
                    self.imageFiles[key] = localURL.lastPathComponent
                    self.misses.removeValue(forKey: key)
                    self.saveIndex()
                }
                self.deliver(key: key, url: localURL ?? remoteURL)
            }
        case .notFound:
            misses[key] = Date()
            saveIndex()
            deliver(key: key, url: nil)
        case .failed:
            deliver(key: key, url: nil)
        }
    }

    private func deliver(key: String, url: URL?) {
        let callbacks = pending.removeValue(forKey: key) ?? []
        callbacks.forEach { $0(url) }
    }

    private func lookUp(name: String, completion: @escaping (LookupResult) -> Void) {
        searchMusicBrainz(artist: name) { [weak self] mbid in
            guard let self = self else { return }
            guard let mbid = mbid else {
                completion(.notFound)
                return
            }
            if mbid.isEmpty {
                completion(.failed)
                return
            }
            self.getArtistRelations(mbid: mbid, completion: completion)
        }
    }

    // MARK: - networking

    /// GET returning parsed json on the main thread; nil json means a network/parse failure
    private func fetchJSON(_ url: URL, completion: @escaping ([String: Any]?) -> Void) {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            var json: [String: Any]? = nil
            if error == nil, let data = data,
               let status = (response as? HTTPURLResponse)?.statusCode, status == 200 {
                json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            }
            DispatchQueue.main.async { completion(json) }
        }.resume()
    }

    /// waits for a free musicbrainz slot, then fetches
    private func fetchMusicBrainz(_ url: URL, completion: @escaping ([String: Any]?) -> Void) {
        let now = Date()
        let slot = max(now, nextMusicBrainzSlot)
        nextMusicBrainzSlot = slot.addingTimeInterval(musicBrainzSpacing)
        DispatchQueue.main.asyncAfter(deadline: .now() + slot.timeIntervalSince(now)) { [weak self] in
            self?.fetchJSON(url, completion: completion)
        }
    }

    // MARK: - musicbrainz search

    /// completion: mbid, nil if no matching artist, "" if the request failed
    private func searchMusicBrainz(artist: String, completion: @escaping (String?) -> Void) {
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/artist/")!
        components.percentEncodedQuery = FormEncoding.query([
            "query": MusicBrainzQuery.artistQuery(artist),
            "limit": "5",
            "fmt": "json"
        ])
        guard let url = components.url else {
            completion(nil)
            return
        }

        fetchMusicBrainz(url) { json in
            guard let json = json else {
                completion("")
                return
            }
            let artists = json["artists"] as? [[String: Any]] ?? []
            let wanted = ArtistImageNaming.normalizedName(artist)
            // prefer an exact name match; otherwise only trust a perfect score
            let exact = artists.first { ArtistImageNaming.normalizedName($0["name"] as? String ?? "") == wanted }
            let confident = artists.first { ($0["score"] as? Int ?? 0) >= 100 }
            completion((exact ?? confident)?["id"] as? String)
        }
    }

    // MARK: - get artist relations (wikimedia link)

    private func getArtistRelations(mbid: String, completion: @escaping (LookupResult) -> Void) {
        guard let url = URL(string: "https://musicbrainz.org/ws/2/artist/\(mbid)?inc=url-rels&fmt=json") else {
            completion(.notFound)
            return
        }

        fetchMusicBrainz(url) { [weak self] json in
            guard let self = self else { return }
            guard let json = json else {
                completion(.failed)
                return
            }
            let relations = json["relations"] as? [[String: Any]] ?? []

            var commonsPage: String?
            var wikidataPage: String?
            for relation in relations {
                guard let type = relation["type"] as? String,
                      let urlInfo = relation["url"] as? [String: Any],
                      let resource = urlInfo["resource"] as? String else { continue }
                if type == "image" && resource.contains("commons.wikimedia.org") && commonsPage == nil {
                    commonsPage = resource
                } else if type == "wikidata" && wikidataPage == nil {
                    wikidataPage = resource
                }
            }

            if let commonsPage = commonsPage, let fileName = Self.commonsFileName(from: commonsPage) {
                self.getWikimediaImageURL(fileName: fileName, completion: completion)
            } else if let wikidataPage = wikidataPage {
                self.getImageFromWikidata(wikidataPage, completion: completion)
            } else {
                completion(.notFound)
            }
        }
    }

    /// "https://commons.wikimedia.org/wiki/File:Some%20Name.jpg" -> "Some Name.jpg"
    private static func commonsFileName(from pageURL: String) -> String? {
        guard let range = pageURL.range(of: "File:") else { return nil }
        let raw = String(pageURL[range.upperBound...])
        let decoded = raw.removingPercentEncoding ?? raw
        return decoded.isEmpty ? nil : decoded
    }

    // MARK: - wikimedia commons

    private func getWikimediaImageURL(fileName: String, completion: @escaping (LookupResult) -> Void) {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.percentEncodedQuery = FormEncoding.query([
            "action": "query",
            "titles": "File:\(fileName)",
            "prop": "imageinfo",
            "iiprop": "url",
            "iiurlwidth": "500",
            "format": "json"
        ])
        guard let url = components.url else {
            completion(.notFound)
            return
        }

        fetchJSON(url) { json in
            guard let json = json else {
                completion(.failed)
                return
            }
            let pages = (json["query"] as? [String: Any])?["pages"] as? [String: Any] ?? [:]
            for (_, pageValue) in pages {
                if let page = pageValue as? [String: Any],
                   let info = (page["imageinfo"] as? [[String: Any]])?.first,
                   let thumb = info["thumburl"] as? String,
                   let imageURL = URL(string: thumb) {
                    completion(.found(imageURL))
                    return
                }
            }
            completion(.notFound)
        }
    }

    // MARK: - wikidata fallback

    private func getImageFromWikidata(_ wikidataURL: String, completion: @escaping (LookupResult) -> Void) {
        guard let entity = wikidataURL.split(separator: "/").last.map(String.init), !entity.isEmpty else {
            completion(.notFound)
            return
        }
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")!
        components.percentEncodedQuery = FormEncoding.query([
            "action": "wbgetclaims",
            "entity": entity,
            "property": "P18",
            "format": "json"
        ])
        guard let url = components.url else {
            completion(.notFound)
            return
        }

        fetchJSON(url) { [weak self] json in
            guard let self = self else { return }
            guard let json = json else {
                completion(.failed)
                return
            }
            if let claims = json["claims"] as? [String: Any],
               let p18 = (claims["P18"] as? [[String: Any]])?.first,
               let mainsnak = p18["mainsnak"] as? [String: Any],
               let datavalue = mainsnak["datavalue"] as? [String: Any],
               let fileName = datavalue["value"] as? String {
                self.getWikimediaImageURL(fileName: fileName, completion: completion)
            } else {
                completion(.notFound)
            }
        }
    }

    // MARK: - local image caching

    /// completion on main: local file url, or nil if the download failed
    private func download(_ url: URL, for artistName: String, completion: @escaping (URL?) -> Void) {
        let localURL = cacheDirectory.appendingPathComponent(ArtistImageNaming.fileName(for: artistName))
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, _, error in
            var saved: URL? = nil
            if error == nil, let data = data, UIImage(data: data) != nil {
                do {
                    try data.write(to: localURL, options: .atomic)
                    saved = localURL
                } catch {
                    print("failed to cache artist image: \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async { completion(saved) }
        }.resume()
    }

    private func saveIndex() {
        let snapshot = StoredIndex(files: imageFiles, misses: misses)
        let file = indexFile
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: file, options: .atomic)
            }
        }
    }

    // MARK: - cache management

    func clearCache() {
        imageFiles.removeAll()
        misses.removeAll()
        let fileManager = FileManager.default
        if let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    // MARK: - cache size

    func cacheSize() -> Int64 {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        return files.reduce(Int64(0)) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }
}
