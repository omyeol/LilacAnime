import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// iOS port of `ReAnimeHarClient`, `ReAnimeHarParser`, and `ReAnimePlayerResolver` / `ReAnimeFlixCloud`.
public final class ReAnimeHarClient: @unchecked Sendable {
    public static let baseURL = "https://reanime.to"
    private static let idPrefix = "reanime:"

    public struct Facets: Codable, Hashable, Sendable {
        public var genres: [String] = []
        public var formats: [String] = []
        public var statuses: [String] = []
        public var seasons: [String] = []
        public var years: [String] = []
        public var tags: [String] = []
        public var studios: [String] = []

        public init(
            genres: [String] = [],
            formats: [String] = [],
            statuses: [String] = [],
            seasons: [String] = [],
            years: [String] = [],
            tags: [String] = [],
            studios: [String] = []
        ) {
            self.genres = genres
            self.formats = formats
            self.statuses = statuses
            self.seasons = seasons
            self.years = years
            self.tags = tags
            self.studios = studios
        }
    }

    private let http = HttpClient.shared

    public init() {}

    public func search(
        query: String = "",
        limit: Int = 36,
        offset: Int = 0,
        genre: [String] = [],
        year: Int? = nil,
        season: String? = nil,
        status: String? = nil,
        format: String? = nil,
        tag: [String] = [],
        character: [String] = [],
        staff: [String] = [],
        studio: [String] = []
    ) async throws -> String {
        var items: [URLQueryItem] = []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "q", value: trimmed)) }
        if !genre.isEmpty { items.append(URLQueryItem(name: "genre", value: genre.joined(separator: ","))) }
        if let year { items.append(URLQueryItem(name: "year", value: String(year))) }
        if let season, !season.isEmpty { items.append(URLQueryItem(name: "season", value: season)) }
        if let status, !status.isEmpty { items.append(URLQueryItem(name: "status", value: status)) }
        if let format, !format.isEmpty { items.append(URLQueryItem(name: "format", value: format)) }
        if !tag.isEmpty { items.append(URLQueryItem(name: "tag", value: tag.joined(separator: ","))) }
        if !character.isEmpty { items.append(URLQueryItem(name: "character", value: character.joined(separator: ","))) }
        if !staff.isEmpty { items.append(URLQueryItem(name: "staff", value: staff.joined(separator: ","))) }
        if !studio.isEmpty { items.append(URLQueryItem(name: "studio", value: studio.joined(separator: ","))) }
        items.append(URLQueryItem(name: "limit", value: String(limit)))
        items.append(URLQueryItem(name: "offset", value: String(offset)))
        return try await request(path: "/api/v1/search", queryItems: items)
    }

    public func facets() async throws -> String {
        return try await request(path: "/api/v1/search", queryItems: [
            URLQueryItem(name: "facets", value: "true"),
            URLQueryItem(name: "limit", value: "0")
        ])
    }

    public func topAnime(period: String = "today", limit: Int = 10) async throws -> String {
        return try await request(path: "/api/v1/top/anime", queryItems: [
            URLQueryItem(name: "period", value: period),
            URLQueryItem(name: "limit", value: String(limit))
        ])
    }

    public func schedule(timeZone: String = "Asia/Seoul", week: Int = 0) async throws -> String {
        return try await request(path: "/api/v1/schedule", queryItems: [
            URLQueryItem(name: "tz", value: timeZone),
            URLQueryItem(name: "week", value: String(week))
        ])
    }

    public func detailData(slug: String) async throws -> String {
        let cleanSlug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            .components(separatedBy: "/anime/").last ?? slug
        return try await request(
            path: "/anime/\(cleanSlug)/__data.json",
            queryItems: [URLQueryItem(name: "x-appkit-invalidated", value: "001")]
        )
    }

    public func watchData(slug: String, episode: Int? = nil) async throws -> String {
        let cleanSlug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
            .components(separatedBy: "/watch/").last ?? slug
        var items = [URLQueryItem(name: "x-appkit-invalidated", value: "001")]
        if let episode, episode > 0 {
            items.append(URLQueryItem(name: "ep", value: String(episode)))
        }
        return try await request(path: "/watch/\(cleanSlug)/__data.json", queryItems: items)
    }

    public func resolveFlixUrl(anilistId: Int, episode: Int) async -> String? {
        guard let raw = try? await request(path: "/api/flix/\(anilistId)/\(episode)", queryItems: []),
              let data = raw.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let servers = root["servers"] as? [[String: Any]] else {
            return nil
        }
        var candidates: [(String, String)] = []
        for s in servers {
            let link = (s["dataLink"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let name = (s["serverName"] as? String) ?? ""
            if link.lowercased().hasPrefix("https://flixcloud.cc/e/") {
                candidates.append((name, link))
            }
        }
        return candidates.first(where: { $0.0.caseInsensitiveCompare("HD-2") == .orderedSame })?.1
            ?? candidates.first(where: { $0.0.localizedCaseInsensitiveContains("HD-2") })?.1
            ?? candidates.first(where: { $0.0.caseInsensitiveCompare("HD-1") == .orderedSame })?.1
            ?? candidates.first?.1
    }

    private func request(path: String, queryItems: [URLQueryItem]) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "reanime.to"
        components.path = path.hasPrefix("/") ? path : "/\(path)"
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url?.absoluteString else {
            throw NetworkError.invalidURL(path)
        }
        let referer = path.contains("api/v1/search") ? "https://reanime.to/search" : "https://reanime.to/"
        return try await http.getText(
            url: url,
            headers: ["Accept": "application/json"],
            referer: referer
        )
    }

    // MARK: - ReAnimeHarParser

    public static func parseSearch(_ json: String) -> [Anime] {
        return parseAnimeCollection(json)
    }

    public static func parseTop(_ json: String) -> [Anime] {
        return parseAnimeCollection(json)
    }

    public static func parseSchedule(_ json: String) -> [Anime] {
        return parseAnimeCollection(json)
    }

    public static func parseFacets(_ json: String) -> Facets {
        guard let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return Facets()
        }
        let facetsObj = (root["facets"] as? [String: Any]) ?? root

        func extractValues(_ keys: [String]) -> [String] {
            for key in keys {
                guard let val = facetsObj[key] ?? root[key] else { continue }
                var list: [String] = []
                if let arr = val as? [Any] {
                    for elem in arr {
                        if let dict = elem as? [String: Any] {
                            let str = (dict["name"] as? String)
                                ?? (dict["value"] as? String)
                                ?? (dict["label"] as? String)
                                ?? ""
                            if !str.isEmpty { list.append(str) }
                        } else if let str = elem as? String, !str.isEmpty {
                            list.append(str)
                        } else if let num = elem as? NSNumber {
                            list.append(num.stringValue)
                        }
                    }
                } else if let dict = val as? [String: Any] {
                    list.append(contentsOf: dict.keys)
                }
                if !list.isEmpty { return Array(NSOrderedSet(array: list)) as? [String] ?? list }
            }
            return []
        }

        return Facets(
            genres: extractValues(["genres", "genre"]),
            formats: extractValues(["formats", "format"]),
            statuses: extractValues(["statuses", "status"]),
            seasons: extractValues(["seasons", "season"]),
            years: extractValues(["years", "season_year", "year"]),
            tags: extractValues(["tags", "tag"]),
            studios: extractValues(["studios", "studio"])
        )
    }

    private static func parseAnimeCollection(_ json: String) -> [Anime] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        var found: [(String, [String: Any])] = []
        var seen = Set<String>()

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if dict["anime_id"] != nil || dict["anilist_id"] != nil || dict["slug"] != nil {
                    let id = (dict["anime_id"] as? String)
                        ?? (dict["slug"] as? String)
                        ?? ((dict["anilist_id"] as? Int).map(String.init) ?? "")
                    if !id.isEmpty && id != "0" && !seen.contains(id) {
                        seen.insert(id)
                        found.append((id, dict))
                    }
                }
                for (_, val) in dict { walk(val) }
            } else if let arr = node as? [Any] {
                for item in arr { walk(item) }
            }
        }
        walk(root)

        return found.compactMap { (id, item) in
            let titleObj = item["title"] as? [String: Any]
            let english = (titleObj?["english"] as? String) ?? (item["english"] as? String) ?? ""
            let romaji = (titleObj?["romaji"] as? String) ?? (item["romaji"] as? String) ?? ""
            let native = (titleObj?["native"] as? String) ?? (item["native"] as? String) ?? ""
            let title = !english.isEmpty ? english : (!romaji.isEmpty ? romaji : ((item["title"] as? String) ?? id))
            let coverObj = item["cover_image"] as? [String: Any]
            let poster = (coverObj?["extra_large"] as? String)
                ?? (coverObj?["large"] as? String)
                ?? (item["poster"] as? String)
                ?? ""
            let backdrop = (item["banner_image"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? poster
            let genres = (item["genres"] as? [String]) ?? []
            let anilistId = (item["anilist_id"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            let malId = (item["mal_id"] as? Int).flatMap { $0 > 0 ? $0 : nil }
            let year = (item["season_year"] as? Int).flatMap { $0 > 0 ? String($0) : nil } ?? ""

            return Anime(
                id: "\(idPrefix)\(id)",
                anilistId: anilistId,
                malId: malId,
                title: title,
                poster: poster,
                backdrop: backdrop,
                genres: genres,
                year: year,
                format: (item["format"] as? String) ?? "",
                source: "reanime",
                romaji: romaji,
                english: english,
                native: native,
                note: (item["status"] as? String) ?? "",
                detailUrl: "\(baseURL)/anime/\(id)"
            )
        }
    }

    /// Parses SvelteKit `__data.json` devalue table for Re:Anime detail & watch endpoints.
    public static func parseDetailAndWatch(detailJson: String, watchJson: String, fallback: Anime) -> Anime {
        let detailTable = DevalueTable(json: detailJson)
        var result = fallback

        var episodesTotal = 0
        if let table = detailTable,
           let root = table.obj(0),
           let animeRef = root["anime"] as? Int,
           let animeObj = table.obj(animeRef) {
            let slug = table.stringRef(animeObj, "anime_id")
                ?? fallback.id.replacingOccurrences(of: idPrefix, with: "")
            let titleObj = table.objRef(animeObj, "title")
            let english = table.stringRef(titleObj, "english") ?? table.stringRef(animeObj, "english") ?? fallback.title
            let native = table.stringRef(titleObj, "native") ?? fallback.native
            let romaji = table.stringRef(titleObj, "romaji") ?? fallback.romaji
            let cover = table.objRef(animeObj, "cover_image")
            let poster = table.stringRef(cover, "extra_large") ?? table.stringRef(cover, "large") ?? fallback.poster
            let genres = table.stringArrayRef(animeObj, "genres")
            let studios = table.objectArrayRef(animeObj, "studios").compactMap { table.stringRef($0, "name") }
            episodesTotal = (animeObj["episodes_total"] as? Int) ?? table.intRef(animeObj, "episodes_total") ?? 0

            let relations = table.objectArrayRef(animeObj, "relations").compactMap { rel -> ReAnimeRelated? in
                guard let relSlug = table.stringRef(rel, "anime_id") else { return nil }
                let relTitle = table.objRef(rel, "title")
                let relCover = table.objRef(rel, "cover_image")
                return ReAnimeRelated(
                    id: "\(idPrefix)\(relSlug)",
                    title: table.stringRef(relTitle, "english") ?? table.stringRef(relTitle, "romaji") ?? relSlug,
                    nativeTitle: table.stringRef(relTitle, "native") ?? "",
                    romaji: table.stringRef(relTitle, "romaji") ?? "",
                    poster: table.stringRef(relCover, "extra_large") ?? table.stringRef(relCover, "large") ?? "",
                    format: table.stringRef(rel, "format") ?? "",
                    relationType: table.stringRef(rel, "relation_type") ?? "",
                    season: table.stringRef(rel, "season") ?? "",
                    seasonYear: table.intRef(rel, "season_year")
                )
            }

            result.id = "\(idPrefix)\(slug)"
            result.anilistId = table.intRef(animeObj, "anilist_id") ?? fallback.anilistId
            result.malId = table.intRef(animeObj, "mal_id") ?? fallback.malId
            result.title = english
            result.english = english
            result.native = native
            result.romaji = romaji
            result.poster = poster
            result.backdrop = table.stringRef(table.objRef(animeObj, "banner_image"), "url") ?? poster
            result.description = table.stringRef(animeObj, "description") ?? fallback.description
            if !genres.isEmpty { result.genres = genres }
            if !studios.isEmpty { result.studios = studios }
            result.format = table.stringRef(animeObj, "format") ?? fallback.format
            result.year = table.intRef(animeObj, "season_year").map(String.init) ?? fallback.year
            result.season = table.stringRef(animeObj, "season") ?? fallback.season
            result.seasonYear = table.intRef(animeObj, "season_year") ?? fallback.seasonYear
            result.reAnimeRelated = relations
            result.detailUrl = "\(baseURL)/anime/\(slug)"
        }

        let slug = result.id.replacingOccurrences(of: idPrefix, with: "")
        var knownEpisodes: [Int: Episode] = [:]
        if let watchTable = DevalueTable(json: watchJson),
           let root = watchTable.obj(0) {
            let refs = watchTable.arrayRef(root, "episodes")
            for ref in refs {
                guard let item = watchTable.obj(ref) else { continue }
                let number = watchTable.intRef(item, "episode_number")
                    ?? watchTable.intRef(item, "number")
                    ?? 0
                guard number > 0 else { continue }
                let epTitle = watchTable.stringRef(item, "title") ?? "Episode \(number)"
                let thumb = watchTable.stringRef(item, "image") ?? watchTable.stringRef(item, "thumbnail") ?? ""
                knownEpisodes[number] = Episode(
                    id: "reanime:\(slug):ep-\(number)",
                    number: number,
                    title: epTitle,
                    videoUrl: "\(baseURL)/watch/\(slug)?ep=\(number)",
                    displayNumber: String(number),
                    nativeTitle: watchTable.stringRef(item, "title_japanese") ?? "",
                    airedDate: watchTable.stringRef(item, "aired") ?? "",
                    isFiller: watchTable.boolRef(item, "filler") ?? false,
                    isRecap: watchTable.boolRef(item, "recap") ?? false,
                    playable: true,
                    thumbnailUrl: thumb
                )
            }
        }

        let total = max(episodesTotal, knownEpisodes.keys.max() ?? 0)
        if total > 0 {
            result.episodes = (1...total).map { num in
                knownEpisodes[num] ?? Episode(
                    id: "reanime:\(slug):ep-\(num)",
                    number: num,
                    title: "Episode \(num)",
                    videoUrl: "\(baseURL)/watch/\(slug)?ep=\(num)",
                    displayNumber: String(num),
                    playable: true
                )
            }
        } else {
            result.episodes = knownEpisodes.values.sorted { $0.number < $1.number }
        }
        return result
    }
}

/// Devalue reference table helper for SvelteKit `__data.json`.
private struct DevalueTable {
    let data: [Any]

    init?(json: String) {
        guard let raw = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let nodes = root["nodes"] as? [[String: Any]] else {
            return nil
        }
        var found: [Any]? = nil
        for node in nodes.reversed() {
            if let arr = node["data"] as? [Any], !arr.isEmpty {
                found = arr
                break
            }
        }
        guard let arr = found else { return nil }
        self.data = arr
    }

    func obj(_ index: Int) -> [String: Any]? {
        guard index >= 0 && index < data.count else { return nil }
        return data[index] as? [String: Any]
    }

    func objRef(_ parent: [String: Any]?, _ key: String) -> [String: Any]? {
        guard let idx = parent?[key] as? Int else { return nil }
        return obj(idx)
    }

    func stringRef(_ parent: [String: Any]?, _ key: String) -> String? {
        guard let val = parent?[key] else { return nil }
        if let s = val as? String { return s }
        if let idx = val as? Int, idx >= 0 && idx < data.count {
            return data[idx] as? String
        }
        return nil
    }

    func intRef(_ parent: [String: Any]?, _ key: String) -> Int? {
        guard let val = parent?[key] else { return nil }
        if let i = val as? Int, i >= 0 && i < data.count, let resolved = data[i] as? Int {
            return resolved
        }
        return val as? Int
    }

    func boolRef(_ parent: [String: Any]?, _ key: String) -> Bool? {
        guard let val = parent?[key] else { return nil }
        if let b = val as? Bool { return b }
        if let i = val as? Int, i >= 0 && i < data.count {
            return data[i] as? Bool
        }
        return nil
    }

    func arrayRef(_ parent: [String: Any]?, _ key: String) -> [Int] {
        guard let idx = parent?[key] as? Int, idx >= 0 && idx < data.count,
              let arr = data[idx] as? [Any] else { return [] }
        return arr.compactMap { $0 as? Int }
    }

    func stringArrayRef(_ parent: [String: Any]?, _ key: String) -> [String] {
        return arrayRef(parent, key).compactMap { idx in
            guard idx >= 0 && idx < data.count else { return nil }
            return data[idx] as? String
        }
    }

    func objectArrayRef(_ parent: [String: Any]?, _ key: String) -> [[String: Any]] {
        return arrayRef(parent, key).compactMap { obj($0) }
    }
}
