import Foundation
import Compression

/// iOS port of `MiruroClient`, `Ohli24Client`, `AnimenosubHttpClient`, and `OnlineAniSkipService`.
public final class MiruroClient: @unchecked Sendable {
    private static let base = "https://www.miruro.cx"
    private static let anilistGraphQL = "https://graphql.anilist.co"
    private let http = HttpClient.shared

    public init() {}

    /// Fetches catalog or search via AniList GraphQL (same data source as Miruro frontend).
    public func catalog(query: String = "", page: Int = 1) async throws -> ([Anime], String?) {
        let gql = """
        query ($page: Int, $perPage: Int, $search: String) {
          Page(page: $page, perPage: $perPage) {
            pageInfo { hasNextPage currentPage }
            media(type: ANIME, sort: [POPULARITY_DESC], search: $search) {
              id idMal format season seasonYear episodes status description
              title { romaji english native }
              coverImage { extraLarge large }
              bannerImage
              genres
            }
          }
        }
        """
        var variables: [String: Any] = ["page": page, "perPage": 24]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { variables["search"] = trimmed }

        let payload = try JSONSerialization.data(withJSONObject: ["query": gql, "variables": variables])
        let (data, resp) = try await http.postData(url: Self.anilistGraphQL, body: payload)
        guard (200...299).contains(resp.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let dataObj = root["data"] as? [String: Any],
              let pageObj = dataObj["Page"] as? [String: Any],
              let mediaList = pageObj["media"] as? [[String: Any]] else {
            return ([], nil)
        }
        let pageInfo = pageObj["pageInfo"] as? [String: Any]
        let hasNext = (pageInfo?["hasNextPage"] as? Bool) ?? false
        let items = mediaList.map { Self.mapAniListMedia($0) }
        return (items, hasNext ? String(page + 1) : nil)
    }

    public func detail(anime: Anime) async throws -> Anime {
        let aid = anime.anilistId ?? Int(anime.id.replacingOccurrences(of: "miruro:", with: "")) ?? 0
        guard aid > 0 else { return anime }
        let gql = """
        query ($id: Int) {
          Media(id: $id, type: ANIME) {
            id idMal format season seasonYear episodes status description
            title { romaji english native }
            coverImage { extraLarge large }
            bannerImage
            genres
            studios(isMain: true) { nodes { name } }
          }
        }
        """
        let payload = try JSONSerialization.data(withJSONObject: ["query": gql, "variables": ["id": aid]])
        let (data, resp) = try await http.postData(url: Self.anilistGraphQL, body: payload)
        guard (200...299).contains(resp.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let media = (root["data"] as? [String: Any])?["Media"] as? [String: Any] else {
            return anime
        }
        var parsed = Self.mapAniListMedia(media)
        let epCount = max((media["episodes"] as? Int) ?? 12, 1)
        parsed.episodes = (1...epCount).map { num in
            Episode(
                id: "miruro:\(aid):\(num)",
                number: num,
                title: "Episode \(num)",
                videoUrl: "\(Self.base)/watch?id=\(aid)&ep=\(num)",
                displayNumber: String(num),
                playable: true
            )
        }
        return parsed
    }

    private static func mapAniListMedia(_ m: [String: Any]) -> Anime {
        let aid = (m["id"] as? Int) ?? 0
        let malId = (m["idMal"] as? Int).flatMap { $0 > 0 ? $0 : nil }
        let titleObj = m["title"] as? [String: Any]
        let english = (titleObj?["english"] as? String) ?? ""
        let romaji = (titleObj?["romaji"] as? String) ?? ""
        let native = (titleObj?["native"] as? String) ?? ""
        let title = !english.isEmpty ? english : (!romaji.isEmpty ? romaji : native)
        let cover = m["coverImage"] as? [String: Any]
        let poster = (cover?["extraLarge"] as? String) ?? (cover?["large"] as? String) ?? ""
        let banner = (m["bannerImage"] as? String) ?? poster
        let desc = HTMLParser.stripTags((m["description"] as? String) ?? "")
        let genres = (m["genres"] as? [String]) ?? []
        let year = (m["seasonYear"] as? Int).map(String.init) ?? ""
        return Anime(
            id: "miruro:\(aid)",
            anilistId: aid,
            malId: malId,
            title: title,
            poster: poster,
            backdrop: banner,
            genres: genres,
            description: desc,
            year: year,
            season: (m["season"] as? String) ?? "",
            seasonYear: m["seasonYear"] as? Int,
            format: (m["format"] as? String) ?? "",
            source: "miruro",
            romaji: romaji,
            english: english,
            native: native,
            note: (m["status"] as? String) ?? "",
            detailUrl: "\(base)/watch?id=\(aid)"
        )
    }
}

/// iOS port of `Ohli24Client` (애니24).
public final class Ohli24Client: @unchecked Sendable {
    public static let base = "https://ohli24.com"
    private let http = HttpClient.shared

    public init() {}

    public func catalog(pageNumber: Int = 1, query: String = "") async throws -> [Anime] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let airing = (try? await fetchPageProps("\(Self.base)/방영중"))
                .flatMap { Self.parseItems($0["items"] as? [[String: Any]]) } ?? []
            let filteredAiring = airing.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
            let finished = (try? await board(name: "완결", page: 1, query: trimmed)) ?? []
            let movies = (try? await board(name: "극장판", page: 1, query: trimmed)) ?? []
            var seen = Set<String>()
            return (filteredAiring + finished + movies).filter { seen.insert($0.id).inserted }
        }
        if pageNumber <= 1 {
            let props = try await fetchPageProps("\(Self.base)/방영중")
            return Self.parseItems(props["items"] as? [[String: Any]])
        } else {
            return try await board(name: "완결", page: pageNumber - 1)
        }
    }

    public func detail(anime: Anime) async throws -> Anime {
        let slug = anime.id.replacingOccurrences(of: "ohli24:", with: "")
        let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        let url = anime.detailUrl.isEmpty ? "\(Self.base)/c/\(encodedSlug)" : anime.detailUrl
        let props = try await fetchPageProps(url)
        guard let comic = props["comic"] as? [String: Any] else { return anime }

        let epsPage = props["episodes"] as? [String: Any]
        let rawList = (epsPage?["data"] as? [[String: Any]]) ?? []
        var episodes: [Episode] = []
        for (idx, raw) in rawList.enumerated() {
            let label = (raw["title"] as? String) ?? "\(idx + 1)화"
            let epSlug = (raw["slug"] as? String) ?? String(idx + 1)
            let number = HTMLParser.firstMatch("(\\d+)", in: label).flatMap(Int.init) ?? (idx + 1)
            let encEpSlug = epSlug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? epSlug
            episodes.append(Episode(
                id: "ohli24:\(slug):\(epSlug)",
                number: number,
                title: label,
                videoUrl: "\(Self.base)/e/\(encEpSlug)",
                displayNumber: String(number),
                airedDate: String(((raw["published_at"] as? String) ?? "").prefix(10))
            ))
        }
        episodes.sort { $0.number < $1.number }

        let thumb = (comic["thumbnail"] as? String).flatMap { $0.isEmpty ? nil : "\(Self.base)/storage/\($0)" } ?? anime.poster
        var updated = anime
        updated.title = (comic["title"] as? String) ?? anime.title
        updated.native = (comic["original_title"] as? String) ?? anime.native
        updated.poster = thumb
        updated.backdrop = thumb
        updated.description = HTMLParser.stripTags((comic["description"] as? String) ?? anime.description)
        updated.source = "ohli24"
        updated.episodes = episodes
        return updated
    }

    public func resolve(episode: Episode) async -> LinkkfApiClient.ResolvedPlayerResult {
        let epUrl = episode.videoUrl ?? ""
        guard !epUrl.isEmpty else {
            return LinkkfApiClient.ResolvedPlayerResult(episodeId: episode.id, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: nil)
        }
        do {
            let props = try await fetchPageProps(epUrl)
            let playingRaw = ((props["playing"] as? [String: Any])?["body"] as? [String: Any])?["url"] as? String ?? ""
            let playing = HTMLParser.resolveURL(playingRaw, base: Self.base)
            guard let playerURL = URL(string: playing),
                  let host = playerURL.host,
                  let scheme = playerURL.scheme else {
                return LinkkfApiClient.ResolvedPlayerResult(episodeId: episode.id, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: epUrl)
            }
            let origin = "\(scheme)://\(host)"
            let comp = URLComponents(string: playing)
            let hash = comp?.queryItems?.first(where: { $0.name == "data" })?.value
                ?? playerURL.lastPathComponent
            let postUrl = "\(origin)/player/index.php?data=\(hash)&do=getVideo"
            let formBody = "hash=\(hash)&r=\(Self.base)/".data(using: .utf8) ?? Data()
            let (data, resp) = try await http.postData(
                url: postUrl,
                body: formBody,
                contentType: "application/x-www-form-urlencoded; charset=UTF-8",
                headers: ["X-Requested-With": "XMLHttpRequest", "Origin": origin],
                referer: playing
            )
            if (200...299).contains(resp.statusCode),
               let info = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let master = (info["securedLink"] as? String) ?? (info["url"] as? String) ?? ""
                if master.hasPrefix("http") {
                    let headers = "User-Agent: \(HttpClient.mobileUserAgent)\nReferer: \(playing)"
                    return LinkkfApiClient.ResolvedPlayerResult(
                        episodeId: episode.id,
                        m3u8Url: master,
                        referer: playing,
                        headers: headers,
                        subtitleUrl: nil,
                        subtitleReferer: playing,
                        playerUrl: playing
                    )
                }
            }
        } catch {}
        return LinkkfApiClient.ResolvedPlayerResult(episodeId: episode.id, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: epUrl)
    }

    private func board(name: String, page: Int, query: String = "") async throws -> [Anime] {
        let encName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        var url = "\(Self.base)/\(encName)"
        var args: [String] = []
        if page > 1 { args.append("page=\(page)") }
        if !query.isEmpty {
            let encQ = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            args.append("keyword=\(encQ)")
        }
        if !args.isEmpty { url += "?" + args.joined(separator: "&") }
        let props = try await fetchPageProps(url)
        let comics = (props["comics"] as? [String: Any])?["data"] as? [[String: Any]]
        return Self.parseItems(comics)
    }

    private func fetchPageProps(_ url: String) async throws -> [String: Any] {
        let html = try await http.getText(url: url, referer: "\(Self.base)/")
        guard let scriptJson = HTMLParser.firstMatch("<script[^>]*data-page=[\"']app[\"'][^>]*>(.*?)</script>", in: html) else {
            throw NetworkError.parseError("애니24 data-page 스크립트를 찾지 못했습니다.")
        }
        let decoded = HTMLParser.decodeEntities(scriptJson)
        guard let data = decoded.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let props = root["props"] as? [String: Any] else {
            throw NetworkError.parseError("애니24 props JSON 파싱 실패")
        }
        return props
    }

    private static func parseItems(_ array: [[String: Any]]?) -> [Anime] {
        guard let array else { return [] }
        return array.compactMap { item in
            let slug = (item["slug"] as? String) ?? ""
            let title = (item["title"] as? String) ?? ""
            guard !slug.isEmpty && !title.isEmpty else { return nil }
            let thumb = (item["thumbnail"] as? String).flatMap { $0.isEmpty ? nil : "\(base)/storage/\($0)" } ?? ""
            let encSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
            return Anime(
                id: "ohli24:\(slug)",
                title: title,
                poster: thumb,
                backdrop: thumb,
                source: "ohli24",
                native: (item["original_title"] as? String) ?? "",
                note: (item["latest_episode_title"] as? String) ?? "",
                detailUrl: "\(base)/c/\(encSlug)"
            )
        }
    }
}

/// iOS port of `OnlineAniSkipService`.
public final class OnlineAniSkipService: @unchecked Sendable {
    public static let shared = OnlineAniSkipService()

    private static let aniSkipBase = "https://api.aniskip.com/v2/skip-times"
    private static let anilistGraphQL = "https://graphql.anilist.co"
    private static let allowedTypes: Set<String> = ["op", "ed", "mixed-op", "mixed-ed", "recap"]

    private let http = HttpClient.shared
    private var malCache: [Int: Int] = [:]
    private var segmentCache: [String: [ChapterSkipSegment]] = [:]

    private init() {}

    public func getSkipSegments(
        title: String,
        episodeNumber: Int,
        episodeLengthSeconds: Int = 0,
        anilistId: Int? = nil,
        malId: Int? = nil
    ) async -> [ChapterSkipSegment] {
        guard episodeNumber > 0 else { return [] }
        let resolvedMalId: Int?
        if let malId, malId > 0 {
            resolvedMalId = malId
        } else if let anilistId, anilistId > 0 {
            resolvedMalId = await resolveMalId(fromAniListId: anilistId)
        } else {
            resolvedMalId = nil
        }

        guard let targetMalId = resolvedMalId else { return [] }
        let cacheKey = "\(targetMalId):\(episodeNumber)"
        if let cached = segmentCache[cacheKey] {
            return cached
        }

        var segments = await requestSkipTimes(malId: targetMalId, episodeNumber: episodeNumber, length: episodeLengthSeconds)
        if segments.isEmpty && episodeLengthSeconds > 0 {
            segments = await requestSkipTimes(malId: targetMalId, episodeNumber: episodeNumber, length: 0)
        }
        let cleaned = segments
            .filter { $0.startTime >= 0 && $0.endTime > $0.startTime }
            .sorted { $0.startTime < $1.startTime }
        segmentCache[cacheKey] = cleaned
        return cleaned
    }

    private func requestSkipTimes(malId: Int, episodeNumber: Int, length: Int) async -> [ChapterSkipSegment] {
        let url = "\(Self.aniSkipBase)/\(malId)/\(episodeNumber)?types[]=op&types[]=ed&types[]=mixed-op&types[]=mixed-ed&types[]=recap&episodeLength=\(max(0, length))"
        guard let text = try? await http.getText(url: url, headers: ["Accept": "application/json"], userAgent: "LilacAnime iOS"),
              let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let results = root["results"] as? [[String: Any]] else {
            return []
        }

        var list: [ChapterSkipSegment] = []
        for item in results {
            guard let type = item["skipType"] as? String, Self.allowedTypes.contains(type) else { continue }
            let interval = (item["interval"] as? [String: Any]) ?? item
            guard let start = (interval["startTime"] as? NSNumber)?.doubleValue,
                  let end = (interval["endTime"] as? NSNumber)?.doubleValue,
                  end > start else { continue }
            let epLen = (item["episodeLength"] as? NSNumber)?.doubleValue ?? 0
            list.append(ChapterSkipSegment(type: type, startTime: start, endTime: end, episodeLength: epLen))
        }
        return list
    }

    private func resolveMalId(fromAniListId anilistId: Int) async -> Int? {
        if let cached = malCache[anilistId] { return cached }
        let query = "query ($id: Int) { Media(id: $id, type: ANIME) { id idMal } }"
        guard let body = try? JSONSerialization.data(withJSONObject: ["query": query, "variables": ["id": anilistId]]),
              let (data, resp) = try? await http.postData(url: Self.anilistGraphQL, body: body, userAgent: "LilacAnime iOS"),
              (200...299).contains(resp.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let media = (root["data"] as? [String: Any])?["Media"] as? [String: Any],
              let idMal = media["idMal"] as? Int, idMal > 0 else {
            return nil
        }
        malCache[anilistId] = idMal
        return idMal
    }
}
