//
//  WebEncoding.swift
//  Jukebox
//
//  URL/form encoding and request signing helpers. Foundation + CryptoKit only,
//  so they can be unit tested.
//

import Foundation
import CryptoKit

enum FormEncoding {
    /// RFC 3986 unreserved characters. everything else (including &, +, =, spaces and
    /// non-ASCII letters) gets percent-encoded.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    /// `a=1&b=2` with keys sorted, for form bodies and query strings
    static func query(_ params: [String: String]) -> String {
        params.keys.sorted()
            .map { "\(encode($0))=\(encode(params[$0] ?? ""))" }
            .joined(separator: "&")
    }
}

enum LastFMSignature {
    /// last.fm api_sig: md5 of every parameter (except format/callback) as key+value sorted by key, then the secret
    static func sign(_ params: [String: String], secret: String) -> String {
        var string = ""
        for key in params.keys.sorted() where key != "format" && key != "callback" {
            string += key + (params[key] ?? "")
        }
        string += secret
        return Insecure.MD5.hash(data: Data(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// a scrobble waiting to be sent to last.fm (kept on disk so offline plays aren't lost)
struct PendingScrobble: Codable, Equatable {
    let artist: String
    let track: String
    let album: String?
    let duration: Int?
    let timestamp: Int // unix time the song started playing

    /// parameters for a batch `track.scrobble` call (last.fm accepts up to 50 at once)
    static func batchParameters(_ scrobbles: [PendingScrobble]) -> [String: String] {
        var params: [String: String] = [:]
        for (i, scrobble) in scrobbles.prefix(50).enumerated() {
            params["artist[\(i)]"] = scrobble.artist
            params["track[\(i)]"] = scrobble.track
            params["timestamp[\(i)]"] = String(scrobble.timestamp)
            if let album = scrobble.album, !album.isEmpty { params["album[\(i)]"] = album }
            if let duration = scrobble.duration, duration > 0 { params["duration[\(i)]"] = String(duration) }
        }
        return params
    }
}

enum MusicBrainzQuery {
    /// a lucene phrase query for an exact artist name, e.g. artist:"Simon & Garfunkel"
    static func artistQuery(_ name: String) -> String {
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "artist:\"\(escaped)\""
    }
}

enum ArtistImageNaming {
    static func normalizedName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// a safe file name for any artist (names can contain "/", "..", emoji, etc.)
    static func fileName(for name: String) -> String {
        let digest = SHA256.hash(data: Data(normalizedName(name).utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
}
