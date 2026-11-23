import Foundation

/// iOS port of `LinkkfApiClient`, `LinkkfParser`, and `LinkkfPlayerResolver`.
public final class LinkkfApiClient: @unchecked Sendable {
    public static let webBase = "https://linkani.tv"

    public struct FilterTag: Identifiable, Codable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var slug: String
        public var count: Int

        public init(id: Int, name: String, slug: String = "", count: Int = 0) {
            self.id = id
            self.name = name
            self.slug = slug
            self.count = count
        }
    }

    public struct FilterResult: Sendable {
        public var items: [Anime]
        public var page: Int
        public var totalPages: Int
        public var totalResults: Int
    }

    public struct EpisodeServer: Identifiable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var episodes: [Episode]
    }

    public struct RelatedSeries: Identifiable, Hashable, Sendable {
        public var id: Int
        public var name: String
        public var count: Int
        public var items: [Anime]
    }

    public struct WatchData: Sendable {
        public var streamUrl: String?
        public var nextStreamUrl: String?
        public var previousPage: String?
        public var nextPage: String?
        public var subtitleUrl: String?
        public var title: String
    }

    public struct ResolvedPlayerResult: Sendable {
        public var episodeId: String
        public var m3u8Url: String?
        public var referer: String?
        public var headers: String?
        public var subtitleUrl: String?
        public var subtitleReferer: String?
        public var playerUrl: String?
        public var flixCloudPk: String? = nil
    }

    private let http = HttpClient.shared

    public init() {}

    public func getHome(page: Int = 1, limit: Int = 12) async throws -> [Anime] {
        let url = page <= 1 ? "\(Self.webBase)/list/2/" : "\(Self.webBase)/list/2/page/\(page)/"
        return try await loadList(url: url, limit: limit)
    }

    public func search(query: String, limit: Int = 60) async throws -> [Anime] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? term
        let urls = [
            "\(Self.webBase)/?s=\(encoded)",
            "\(Self.webBase)/search/?s=\(encoded)"
        ]
        for url in urls {
            if let parsed = try? await loadList(url: url, limit: limit), !parsed.isEmpty {
                return parsed
            }
        }
        let key = normalizeSearch(term)
        var collected: [Anime] = []
        var seen = Set<String>()
        for page in 1...6 {
            if let items = try? await getHome(page: page, limit: 60) {
                for item in items where !seen.contains(item.id) {
                    let hay = normalizeSearch("\(item.title) \(item.native) \(item.romaji) \(item.english)")
                    if hay.contains(key) {
                        seen.insert(item.id)
                        collected.append(item)
                        if collected.count >= limit { return collected }
                    }
                }
            }
        }
        return collected
    }

    public func getSchedule(categoryTagId: Int, limit: Int = 50) async throws -> [Anime] {
        let day: String? = switch categoryTagId {
        case 21189: "월"
        case 21190: "화"
        case 21191: "수"
        case 21192: "목"
        case 21193: "금"
        case 21194: "토"
        case 21195: "일"
        default: nil
        }
        guard let day else { return try await getHome(page: 1, limit: limit) }
        let encoded = day.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? day
        return try await loadList(url: "\(Self.webBase)/list/2/class/\(encoded)/", limit: limit)
    }

    public func getSeasonType(tagId: Int, limit: Int = 20) async throws -> [Anime] {
        let route: String = switch tagId {
        case 5086: "\(Self.webBase)/label/topday/"
        case 5061: "\(Self.webBase)/list/2/lang/Movie/"
        case 5085: "\(Self.webBase)/list/9/"
        default: "\(Self.webBase)/list/2/"
        }
        return try await loadList(url: route, limit: limit)
    }

    public func getFilterTags(taxonomy: String) async throws -> [FilterTag] {
        let html = try await http.getText(url: "\(Self.webBase)/list/2/", referer: "\(Self.webBase)/")
        let pathMarker: String = switch taxonomy {
        case "anime-seasontype": "/list/2/lang/"
        case "anigenres": "/list/2/class/"
        case "anime-seasonys": "/list/2/year/"
        default: ""
        }
        guard !pathMarker.isEmpty else { return [] }

        let anchorMatches = HTMLParser.allMatches("<a\\b[^>]*href\\s*=\\s*[\"']([^\"']*\(NSRegularExpression.escapedPattern(for: pathMarker))[^\"']*)[\"'][^>]*>(.*?)</a>", in: html)
        let excludedWeekdays: Set<String> = ["월", "화", "수", "목", "금", "토", "일", "genres", "year", "type", "anime"]
        var result: [FilterTag] = []
        var seen = Set<Int>()
        for match in anchorMatches where match.count >= 3 {
            let href = match[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let name = HTMLParser.stripTags(match[2])
            if name.isEmpty || href.isEmpty { continue }
            if excludedWeekdays.contains(name.lowercased()) { continue }
            let id = stableId(href)
            if !seen.contains(id) {
                seen.insert(id)
                result.append(FilterTag(id: id, name: name, slug: href))
            }
        }
        return result
    }

    public func getFilteredAnime(
        page: Int = 1,
        limit: Int = 20,
        seasonTypeIds: [Int] = [],
        genreIds: [Int] = [],
        yearIds: [Int] = []
    ) async throws -> FilterResult {
        let routeId = genreIds.first ?? yearIds.first ?? seasonTypeIds.first
        var route = "\(Self.webBase)/list/2/"
        if let targetId = routeId,
           let html = try? await http.getText(url: "\(Self.webBase)/list/2/", referer: "\(Self.webBase)/") {
            let links = HTMLParser.allMatches("<a\\b[^>]*href\\s*=\\s*[\"']([^\"']+)[\"']", in: html)
            if let found = links.first(where: { $0.count > 1 && stableId($0[1]) == targetId })?[1] {
                route = HTMLParser.resolveURL(found, base: Self.webBase)
            }
        }
        let pagedUrl: String
        if page <= 1 {
            pagedUrl = route
        } else {
            pagedUrl = route.hasSuffix("/") ? "\(route)page/\(page)/" : "\(route)/page/\(page)/"
        }
        let html = try await http.getText(url: pagedUrl, referer: "\(Self.webBase)/")
        let items = Self.parseAnimeList(html: html, limit: limit)
        let pageMatches = HTMLParser.allMatches("/page/(\\d+)/?[\"']", in: html)
        let maxPage = pageMatches.compactMap { $0.count > 1 ? Int($0[1]) : nil }.max() ?? 1
        return FilterResult(items: items, page: min(page, maxPage), totalPages: maxPage, totalResults: items.count)
    }

    public func getAnime(postId: String) async throws -> Anime? {
        let trimmed = postId.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !trimmed.isEmpty else { return nil }
        let url = "\(Self.webBase)/ani/\(trimmed)/"
        let html = try await http.getText(url: url, referer: "\(Self.webBase)/")
        let seedTitle = HTMLParser.firstMatch("<[^>]*class\\s*=\\s*[\"'][^\"']*detail-info-title[^\"']*[\"'][^>]*>(.*?)</", in: html)
            .map(HTMLParser.stripTags) ?? ""
        let seed = Anime(id: trimmed, title: seedTitle, detailUrl: url)
        return Self.parseAnimeDetail(html: html, original: seed)
    }

    public func getEpisodes(postId: String) async throws -> [Episode] {
        return try await getAnime(postId: postId)?.episodes ?? []
    }

    public func getEpisodeServers(postId: String) async throws -> [EpisodeServer] {
        let eps = try await getEpisodes(postId: postId)
        guard !eps.isEmpty else { return [] }
        return [EpisodeServer(id: 1, name: "DB", episodes: eps)]
    }

    public func getRelatedSeries(currentPostId: String) async throws -> [RelatedSeries] {
        guard let anime = try await getAnime(postId: currentPostId) else { return [] }
        let html = try await http.getText(url: anime.detailUrl, referer: "\(Self.webBase)/")
        guard let actorBox = HTMLParser.firstMatch("<div[^>]*class\\s*=\\s*[\"'][^\"']*detail-actor-box[^\"']*[\"'][^>]*>(.*?)</div>\\s*</div>", in: html) else {
            return []
        }
        let items = Self.parseAnimeList(html: actorBox, limit: 24).filter { $0.id != currentPostId }
        guard !items.isEmpty else { return [] }
        return [RelatedSeries(id: 1, name: "관련 애니", count: items.count, items: items)]
    }

    /// Direct Linkkf watch-page resolver (`var player_aaaa = {...}`).
    public func resolvePlayer(episode: Episode) async -> ResolvedPlayerResult {
        let watchPageUrl = episode.videoUrl ?? ""
        guard !watchPageUrl.isEmpty else {
            return ResolvedPlayerResult(episodeId: episode.id, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: nil)
        }
        let pageUrl = HTMLParser.resolveURL(watchPageUrl, base: Self.webBase)
        for attempt in 0..<3 {
            do {
                let html = try await http.getText(url: pageUrl, referer: "\(Self.webBase)/")
                if let watch = Self.parseWatch(html: html),
                   let stream = watch.streamUrl,
                   stream.lowercased().contains(".m3u8") {
                    let headers = [
                        "Origin: https://linkani.tv",
                        "Referer: https://linkani.tv/",
                        "User-Agent: \(HttpClient.mobileUserAgent)"
                    ].joined(separator: "\n")
                    return ResolvedPlayerResult(
                        episodeId: episode.id,
                        m3u8Url: stream.trimmingCharacters(in: .whitespacesAndNewlines),
                        referer: "https://linkani.tv/",
                        headers: headers,
                        subtitleUrl: watch.subtitleUrl,
                        subtitleReferer: "https://linkani.tv/",
                        playerUrl: pageUrl
                    )
                }
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt == 0 ? 350_000_000 : 900_000_000))
                }
            }
        }
        return ResolvedPlayerResult(episodeId: episode.id, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: pageUrl)
    }

    private func loadList(url: String, limit: Int) async throws -> [Anime] {
        let html = try await http.getText(url: url, referer: "\(Self.webBase)/")
        return Self.parseAnimeList(html: html, limit: limit)
    }

    // MARK: - Static HTML Parsers (LinkkfParser equivalent)

    public static func parseAnimeList(html: String, limit: Int = Int.max) -> [Anime] {
        let itemBlocks = HTMLParser.allMatches("<div[^>]*class\\s*=\\s*[\"'][^\"']*\\bvod-item\\b[^\"']*[\"'][^>]*>(.*?)</div>\\s*(?=<div[^>]*class\\s*=\\s*[\"'][^\"']*\\bvod-item\\b|</div>|$)", in: html)
        var results: [Anime] = []
        var seen = Set<String>()

        let candidateBlocks = itemBlocks.isEmpty
            ? html.components(separatedBy: "vod-item").dropFirst().map { "<div class=\"vod-item" + $0 }
            : itemBlocks.map { $0[0] }

        for block in candidateBlocks {
            let href = HTMLParser.firstMatch("<h3[^>]*class\\s*=\\s*[\"'][^\"']*vod-item-title[^\"']*[\"'][^>]*>\\s*<a[^>]*href\\s*=\\s*[\"']([^\"']+)[\"']", in: block)
                ?? HTMLParser.firstMatch("<a[^>]*class\\s*=\\s*[\"'][^\"']*vod-item-img[^\"']*[\"'][^>]*href\\s*=\\s*[\"']([^\"']+)[\"']", in: block)
                ?? HTMLParser.firstMatch("<a[^>]*href\\s*=\\s*[\"']([^\"']*/ani/[^\"']+)[\"']", in: block)
            guard let rawHref = href else { continue }
            let detailUrl = HTMLParser.resolveURL(rawHref, base: webBase)

            let titleRaw = HTMLParser.firstMatch("<h3[^>]*class\\s*=\\s*[\"'][^\"']*vod-item-title[^\"']*[\"'][^>]*>(.*?)</h3>", in: block)
                ?? HTMLParser.firstMatch("title\\s*=\\s*[\"']([^\"']+)[\"']", in: block)
            let title = HTMLParser.stripTags(titleRaw ?? "")
            if detailUrl.isEmpty || title.isEmpty { continue }

            let imageRaw = HTMLParser.firstMatch("data-original\\s*=\\s*[\"']([^\"']+)[\"']", in: block)
                ?? HTMLParser.firstMatch("<img[^>]*src\\s*=\\s*[\"']([^\"']+)[\"']", in: block)
                ?? ""
            let poster = HTMLParser.resolveURL(imageRaw, base: webBase)
            let note = HTMLParser.firstMatch("<[^>]*class\\s*=\\s*[\"'][^\"']*vod-item-desc[^\"']*[\"'][^>]*>(.*?)</", in: block)
                .map(HTMLParser.stripTags) ?? ""
            let id = detailUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "/").last ?? detailUrl

            if !seen.contains(id) {
                seen.insert(id)
                results.append(
                    Anime(
                        id: id,
                        title: title,
                        poster: poster,
                        backdrop: poster,
                        description: "",
                        source: "linkkf",
                        note: note,
                        detailUrl: detailUrl,
                        episodes: []
                    )
                )
                if results.count >= limit { break }
            }
        }
        return results
    }

    public static func parseAnimeDetail(html: String, original: Anime) -> Anime {
        let title = HTMLParser.firstMatch("<[^>]*class\\s*=\\s*[\"'][^\"']*detail-info-title[^\"']*[\"'][^>]*>(.*?)</", in: html)
            .map(HTMLParser.stripTags)
            .flatMap { $0.isEmpty ? nil : $0 } ?? original.title

        let posterRaw = HTMLParser.firstMatch("<div[^>]*class\\s*=\\s*[\"'][^\"']*detail-img[^\"']*[\"'][^>]*>.*?data-original\\s*=\\s*[\"']([^\"']+)[\"']", in: html)
            ?? HTMLParser.firstMatch("<div[^>]*class\\s*=\\s*[\"'][^\"']*detail-img[^\"']*[\"'][^>]*>.*?<img[^>]*src\\s*=\\s*[\"']([^\"']+)[\"']", in: html)
            ?? original.poster
        let poster = HTMLParser.resolveURL(posterRaw, base: webBase)

        let description = HTMLParser.firstMatch("<meta[^>]*name\\s*=\\s*[\"']description[\"'][^>]*content\\s*=\\s*[\"']([^\"']*)[\"']", in: html)
            .map(HTMLParser.decodeEntities)
            .flatMap { $0.isEmpty ? nil : $0 } ?? original.description

        let infoLines: [String] = {
            guard let ulBlock = HTMLParser.firstMatch("<[^>]*class\\s*=\\s*[\"'][^\"']*detail-info-desc[^\"']*[\"'][^>]*>(.*?)</(?:ul|div)>", in: html) else {
                return []
            }
            return HTMLParser.allMatches("<li[^>]*>(.*?)</li>", in: ulBlock).compactMap { match in
                guard match.count > 1 else { return nil }
                return HTMLParser.stripTags(match[1])
            }
        }()

        func infoValue(_ prefixes: [String]) -> String {
            for line in infoLines {
                if prefixes.contains(where: { line.lowercased().hasPrefix($0.lowercased()) }) {
                    if let idx = line.firstIndex(of: "：") ?? line.firstIndex(of: ":") {
                        return line[line.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            return ""
        }

        let genres = infoValue(["장르"]).split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let studios = infoValue(["제작사"]).split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let year = infoValue(["년", "년도"]).replacingOccurrences(of: "년", with: "").trimmingCharacters(in: .whitespaces)
        let format = infoValue(["분류"])
        let native = infoValue(["원제"])
        let anilistId = HTMLParser.firstMatch("anilist-(\\d+)", in: poster).flatMap { Int($0) } ?? original.anilistId

        var updated = original
        updated.title = title
        updated.poster = poster
        updated.backdrop = poster
        updated.description = description
        updated.genres = genres
        updated.airedDate = year
        updated.year = year
        updated.format = format
        updated.studios = studios
        updated.native = native
        updated.anilistId = anilistId
        updated.source = "linkkf"
        updated.episodes = parseEpisodes(html: html, anime: updated)
        return updated
    }

    public static func parseEpisodes(html: String, anime: Anime) -> [Episode] {
        let epMatches = HTMLParser.allMatches("<a\\b[^>]*href\\s*=\\s*[\"']([^\"']*/watch/[^\"']+)[\"'][^>]*>(.*?)</a>", in: html)
        var episodes: [Episode] = []
        var seen = Set<String>()

        for match in epMatches where match.count >= 3 {
            let href = HTMLParser.resolveURL(match[1], base: webBase)
            let rawText = HTMLParser.stripTags(match[2])
            let numMatch = HTMLParser.allMatches("(\\d+)([A-Za-z]+)?", in: rawText).first
                ?? HTMLParser.allMatches("/k(\\d+)([A-Za-z]+)?/?$", in: href).first
            guard let nm = numMatch, nm.count >= 2, let number = Int(nm[1]) else { continue }
            let suffix = nm.count > 2 ? nm[2].lowercased() : ""
            let display = "\(number)\(suffix)"
            guard !href.isEmpty, !seen.contains(href) else { continue }
            seen.insert(href)
            episodes.append(
                Episode(
                    id: "\(anime.id)_ep_\(display.lowercased())",
                    number: number,
                    title: "\(display)화",
                    description: "\(anime.title) \(display)화",
                    videoUrl: href,
                    displayNumber: display
                )
            )
        }
        return episodes.sorted { lhs, rhs in
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            return lhs.displayNumber < rhs.displayNumber
        }
    }

    public static func parseWatch(html: String) -> WatchData? {
        guard let markerRange = html.range(of: "var player_aaaa") else { return nil }
        let suffix = html[markerRange.lowerBound...]
        guard let braceStart = suffix.firstIndex(of: "{") else { return nil }

        var depth = 0
        var quoted = false
        var escaped = false
        var endIndex: String.Index? = nil
        var idx = braceStart
        while idx < suffix.endIndex {
            let c = suffix[idx]
            if quoted {
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    quoted = false
                }
            } else {
                if c == "\"" {
                    quoted = true
                } else if c == "{" {
                    depth += 1
                } else if c == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = suffix.index(after: idx)
                        break
                    }
                }
            }
            idx = suffix.index(after: idx)
        }

        guard let end = endIndex else { return nil }
        let jsonText = String(suffix[braceStart..<end])
            .replacingOccurrences(of: "\\u0026", with: "&")
            .replacingOccurrences(of: "\\/", with: "/")
        guard let data = jsonText.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }

        func nonEmpty(_ raw: Any?) -> String? {
            guard let s = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            return s
        }
        let streamUrl = nonEmpty(obj["actual_url"]) ?? nonEmpty(obj["url"])
        let nextStreamUrl = nonEmpty(obj["url_next"])
        let prevPage = nonEmpty(obj["link_pre"])
        let nextPage = nonEmpty(obj["link_next"])
        let subtitleUrl = nonEmpty(obj["subtitle_url"])
        let vodData = obj["vod_data"] as? [String: Any]
        let title = (vodData?["vod_name"] as? String) ?? ""

        return WatchData(
            streamUrl: streamUrl,
            nextStreamUrl: nextStreamUrl,
            previousPage: prevPage,
            nextPage: nextPage,
            subtitleUrl: subtitleUrl,
            title: title
        )
    }

    private func normalizeSearch(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: "[\\s\\-_:·.,!?\"'()\\[\\]~]+", with: "", options: .regularExpression)
    }

    private func stableId(_ route: String) -> Int {
        var hash: Int32 = 0
        for scalar in route.unicodeScalars {
            hash = 31 &* hash &+ Int32(bitPattern: scalar.value)
        }
        return hash == Int32.min ? 1 : Int(abs(hash))
    }
}
