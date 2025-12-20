//
//  ArtistImageManager.swift
//  Jukebox
//
//  fetches artist images from musicbrainz + wikimedia commons
//

import Foundation
import UIKit

class ArtistImageManager {
    static let shared = ArtistImageManager()
    
    private let userAgent = "Jukebox/1.0 (iOS Music Player)"
    private var memoryCache: [String: URL] = [:]
    private let cacheDirectory: URL
    private let urlCacheFile: URL
    private var diskCache: [String: String] = [:]  // artist name -> url string
    
    private init() {
        // setup cache directory
        let fileManager = FileManager.default
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("ArtistImages", isDirectory: true)
        urlCacheFile = cacheDirectory.appendingPathComponent("url_cache.json")
        
        // create directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        // load disk cache
        loadDiskCache()
    }
    
    // MARK: - public api
    
    func getArtistImage(name: String, completion: @escaping (URL?) -> Void) {
        let normalizedName = name.lowercased().trimmingCharacters(in: .whitespaces)
        
        // check memory cache first
        if let cachedURL = memoryCache[normalizedName] {
            completion(cachedURL)
            return
        }
        
        // check disk cache
        if let urlString = diskCache[normalizedName], let url = URL(string: urlString) {
            memoryCache[normalizedName] = url
            completion(url)
            return
        }
        
        // search musicbrainz for artist
        searchMusicBrainz(artist: name) { [weak self] mbid in
            guard let mbid = mbid else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // get artist relations from musicbrainz
            self?.getArtistRelations(mbid: mbid) { [weak self] remoteURL in
                guard let remoteURL = remoteURL else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                
                // download and cache the image locally
                self?.downloadAndCacheImage(from: remoteURL, for: name) { localURL in
                    if let url = localURL {
                        self?.memoryCache[normalizedName] = url
                        self?.diskCache[normalizedName] = url.absoluteString
                        self?.saveDiskCache()
                    }
                    DispatchQueue.main.async {
                        completion(localURL)
                    }
                }
            }
        }
    }
    
    // MARK: - disk cache
    
    private func loadDiskCache() {
        guard FileManager.default.fileExists(atPath: urlCacheFile.path) else { return }
        
        do {
            let data = try Data(contentsOf: urlCacheFile)
            diskCache = try JSONDecoder().decode([String: String].self, from: data)
            print("loaded \(diskCache.count) cached artist image urls")
        } catch {
            print("failed to load artist image cache: \(error)")
        }
    }
    
    private func saveDiskCache() {
        do {
            let data = try JSONEncoder().encode(diskCache)
            try data.write(to: urlCacheFile)
        } catch {
            print("failed to save artist image cache: \(error)")
        }
    }
    
    // MARK: - musicbrainz search
    
    private func searchMusicBrainz(artist: String, completion: @escaping (String?) -> Void) {
        guard let encodedArtist = artist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            completion(nil)
            return
        }
        
        let urlString = "https://musicbrainz.org/ws/2/artist/?query=artist:\(encodedArtist)&limit=1&fmt=json"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let artists = json["artists"] as? [[String: Any]],
                   let firstArtist = artists.first,
                   let mbid = firstArtist["id"] as? String {
                    completion(mbid)
                } else {
                    completion(nil)
                }
            } catch {
                print("musicbrainz parse error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - get artist relations (wikimedia link)
    
    private func getArtistRelations(mbid: String, completion: @escaping (URL?) -> Void) {
        let urlString = "https://musicbrainz.org/ws/2/artist/\(mbid)?inc=url-rels&fmt=json"
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let relations = json["relations"] as? [[String: Any]] {
                    
                    // look for wikimedia commons or wikipedia image
                    for relation in relations {
                        if let type = relation["type"] as? String,
                           let urlInfo = relation["url"] as? [String: Any],
                           let resource = urlInfo["resource"] as? String {
                            
                            // check for wikimedia commons
                            if type == "image" && resource.contains("commons.wikimedia.org") {
                                self?.getWikimediaImageURL(from: resource, completion: completion)
                                return
                            }
                            
                            // check for wikidata
                            if type == "wikidata" {
                                self?.getImageFromWikidata(resource, completion: completion)
                                return
                            }
                        }
                    }
                    
                    // no image found
                    completion(nil)
                }
            } catch {
                print("musicbrainz relations parse error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - wikimedia commons
    
    private func getWikimediaImageURL(from commonsURL: String, completion: @escaping (URL?) -> Void) {
        // extract filename from commons url
        guard let filename = commonsURL.components(separatedBy: "File:").last else {
            completion(nil)
            return
        }
        
        let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename
        let apiURL = "https://commons.wikimedia.org/w/api.php?action=query&titles=File:\(encodedFilename)&prop=imageinfo&iiprop=url&iiurlwidth=500&format=json"
        
        guard let url = URL(string: apiURL) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let query = json["query"] as? [String: Any],
                   let pages = query["pages"] as? [String: Any] {
                    
                    for (_, pageValue) in pages {
                        if let pageDict = pageValue as? [String: Any],
                           let imageinfo = pageDict["imageinfo"] as? [[String: Any]],
                           let firstImage = imageinfo.first,
                           let thumburl = firstImage["thumburl"] as? String,
                           let imageURL = URL(string: thumburl) {
                            completion(imageURL)
                            return
                        }
                    }
                }
                completion(nil)
            } catch {
                print("wikimedia parse error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - wikidata fallback
    
    private func getImageFromWikidata(_ wikidataURL: String, completion: @escaping (URL?) -> Void) {
        // extract wikidata id (e.g., Q12345)
        guard let wikidataID = wikidataURL.components(separatedBy: "/").last else {
            completion(nil)
            return
        }
        
        let apiURL = "https://www.wikidata.org/w/api.php?action=wbgetclaims&entity=\(wikidataID)&property=P18&format=json"
        
        guard let url = URL(string: apiURL) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let claims = json["claims"] as? [String: Any],
                   let p18 = claims["P18"] as? [[String: Any]],
                   let firstClaim = p18.first,
                   let mainsnak = firstClaim["mainsnak"] as? [String: Any],
                   let datavalue = mainsnak["datavalue"] as? [String: Any],
                   let filename = datavalue["value"] as? String {
                    
                    // construct commons url and get actual image
                    let commonsURL = "https://commons.wikimedia.org/wiki/File:\(filename)"
                    self?.getWikimediaImageURL(from: commonsURL, completion: completion)
                    return
                }
                completion(nil)
            } catch {
                print("wikidata parse error: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    // MARK: - local image caching
    
    private func downloadAndCacheImage(from url: URL, for artistName: String, completion: @escaping (URL?) -> Void) {
        let normalizedName = artistName.lowercased().trimmingCharacters(in: .whitespaces)
        let localFileName = normalizedName.replacingOccurrences(of: " ", with: "_") + ".jpg"
        let localURL = cacheDirectory.appendingPathComponent(localFileName)
        
        // check if already cached locally
        if FileManager.default.fileExists(atPath: localURL.path) {
            completion(localURL)
            return
        }
        
        // download image
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                completion(url) // fallback to remote url
                return
            }
            
            // save to local cache
            do {
                try data.write(to: localURL)
                completion(localURL)
            } catch {
                print("failed to cache image: \(error)")
                completion(url) // fallback to remote url
            }
        }.resume()
    }
    
    // MARK: - cache management
    
    func clearCache() {
        memoryCache.removeAll()
        diskCache.removeAll()
        
        // remove all files in cache directory
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
        
        var totalSize: Int64 = 0
        for file in files {
            if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
               let size = attributes[.size] as? Int64 {
                totalSize += size
            }
        }
        return totalSize
    }
}

