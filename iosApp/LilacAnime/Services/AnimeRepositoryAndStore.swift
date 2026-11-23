import Foundation
import AVFoundation

/// iOS port of `OfflineStore`, `MpvOfflineStore`, and `EpisodeDownloadManager` (using `AVAssetDownloadURLSession` & local file store).
public final class OfflineStore: @unchecked Sendable {
    public static let shared = OfflineStore()

    public struct DownloadStatus: Identifiable, Codable, Hashable, Sendable {
        public var id: String // "\(animeId)::\(episodeId)"
        public var animeId: String
        public var episodeId: String
        public var episodeNumber: Int
        public var title: String
        public var state: String // queued, downloading, completed, failed
        public var progress: Float
        public var localPath: String?
        public var updatedAt: Int64
    }

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    public var rootDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("LilacOffline", isDirectory: true)
    }

    // MARK: - PlayerSettings

    public func getPlayerSettings() -> PlayerSettings {
        guard let data = defaults.data(forKey: "lilac_player_settings"),
              let decoded = try? decoder.decode(PlayerSettings.self, from: data) else {
            return PlayerSettings()
        }
        return decoded
    }

    public func savePlayerSettings(_ settings: PlayerSettings) {
        if let data = try? encoder.encode(settings) {
            defaults.set(data, forKey: "lilac_player_settings")
        }
    }

    // MARK: - ThemeMode

    public func getThemeMode() -> ThemeMode {
        let raw = defaults.string(forKey: "lilac_theme_mode") ?? ThemeMode.system.rawValue
        return ThemeMode(rawValue: raw) ?? .system
    }

    public func saveThemeMode(_ mode: ThemeMode) {
        defaults.set(mode.rawValue, forKey: "lilac_theme_mode")
    }

    // MARK: - Library & Watch History

    public func getLibrary() -> Set<String> {
        let arr = defaults.stringArray(forKey: "lilac_library_ids") ?? []
        return Set(arr)
    }

    public func saveLibrary(_ ids: Set<String>) {
        defaults.set(Array(ids), forKey: "lilac_library_ids")
    }

    public func getWatchHistory() -> [WatchProgress] {
        guard let data = defaults.data(forKey: "lilac_watch_history"),
              let list = try? decoder.decode([WatchProgress].self, from: data) else {
            return []
        }
        return list.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func saveWatchHistory(_ history: [WatchProgress]) {
        if let data = try? encoder.encode(history) {
            defaults.set(data, forKey: "lilac_watch_history")
        }
    }

    // MARK: - Anime & Catalog Cache

    public func saveAnime(_ anime: Anime) {
        let dir = rootDirectory.appendingPathComponent("anime", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeId = Self.safeFilename(anime.id)
        let url = dir.appendingPathComponent("\(safeId).json")
        if let data = try? encoder.encode(anime) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func getAnime(id: String) -> Anime? {
        let safeId = Self.safeFilename(id)
        let url = rootDirectory.appendingPathComponent("anime/\(safeId).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Anime.self, from: data)
    }

    public func saveAnimeList(_ list: [Anime], source: String, markFresh: Bool = true) {
        let dir = rootDirectory.appendingPathComponent("catalog", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(Self.safeFilename(source)).json")
        if let data = try? encoder.encode(list) {
            try? data.write(to: url, options: .atomic)
        }
        if markFresh {
            defaults.set(Date().timeIntervalSince1970, forKey: "catalog_ts_\(source)")
        }
    }

    public func getSavedAnimeList(source: String) -> [Anime] {
        let url = rootDirectory.appendingPathComponent("catalog/\(Self.safeFilename(source)).json")
        guard let data = try? Data(contentsOf: url),
              let list = try? decoder.decode([Anime].self, from: data) else {
            return []
        }
        return list
    }

    public func isAnimeListCacheFresh(source: String, ttlSeconds: TimeInterval = 12 * 3600) -> Bool {
        let ts = defaults.double(forKey: "catalog_ts_\(source)")
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < ttlSeconds
    }

    // MARK: - Episode Downloads

    public func listDownloadStatuses() -> [DownloadStatus] {
        guard let data = defaults.data(forKey: "lilac_download_statuses"),
              let list = try? decoder.decode([DownloadStatus].self, from: data) else {
            return []
        }
        return list
    }

    public func updateDownloadStatus(_ status: DownloadStatus) {
        var current = listDownloadStatuses()
        if let idx = current.firstIndex(where: { $0.id == status.id }) {
            current[idx] = status
        } else {
            current.append(status)
        }
        if let data = try? encoder.encode(current) {
            defaults.set(data, forKey: "lilac_download_statuses")
        }
    }

    public func removeDownload(animeId: String, episode: Episode) {
        let key = "\(animeId)::\(episode.id)"
        var current = listDownloadStatuses()
        if let existing = current.first(where: { $0.id == key || ($0.animeId == animeId && $0.episodeNumber == episode.number) }),
           let localPath = existing.localPath {
            try? fileManager.removeItem(atPath: localPath)
        }
        current.removeAll { $0.id == key || ($0.animeId == animeId && $0.episodeNumber == episode.number) }
        if let data = try? encoder.encode(current) {
            defaults.set(data, forKey: "lilac_download_statuses")
        }
    }

    public func completedPathForEpisode(animeId: String, episodeId: String, episodeNumber: Int) -> String? {
        let statuses = listDownloadStatuses()
        guard let found = statuses.first(where: {
            $0.state == "completed" &&
            $0.animeId == animeId &&
            ($0.episodeId == episodeId || $0.episodeNumber == episodeNumber)
        }), let path = found.localPath, fileManager.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    public static func safeFilename(_ input: String) -> String {
        input.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }
}

/// Unified AnimeRepository matching Android's `com.lilac.anime.data.AnimeRepository`.
public final class AnimeRepository: @unchecked Sendable {
    public let linkkfApi = LinkkfApiClient()
    public let reAnimeHarClient = ReAnimeHarClient()
    public let miruroClient = MiruroClient()
    public let ohli24Client = Ohli24Client()

    public init() {}

    public func getHomeAnimeList(source: String = "linkkf") async throws -> [Anime] {
        switch source {
        case "miruro":
            return try await miruroClient.catalog().0
        case "ohli24":
            return try await ohli24Client.catalog(pageNumber: 1)
        case "reanime":
            let json = try await reAnimeHarClient.search(limit: 36, offset: 0)
            return ReAnimeHarClient.parseSearch(json)
        default:
            return try await linkkfApi.getHome(page: 1, limit: 12)
        }
    }

    public func getAllAnimeListStream(source: String = "linkkf") -> AsyncStream<[Anime]> {
        AsyncStream { continuation in
            Task {
                var result: [Anime] = []
                var seen = Set<String>()

                func appendAndYield(_ items: [Anime]) {
                    var added = false
                    for item in items where !seen.contains(item.id) {
                        seen.insert(item.id)
                        result.append(item)
                        added = true
                    }
                    if added {
                        continuation.yield(result)
                    }
                }

                switch source {
                case "miruro":
                    for page in 1...15 {
                        guard !Task.isCancelled else { break }
                        guard let (items, next) = try? await miruroClient.catalog(page: page), !items.isEmpty else { break }
                        appendAndYield(items)
                        if next == nil { break }
                        try? await Task.sleep(nanoseconds: 120_000_000)
                    }
                case "ohli24":
                    for page in 1...30 {
                        guard !Task.isCancelled else { break }
                        guard let items = try? await ohli24Client.catalog(pageNumber: page), !items.isEmpty else { break }
                        appendAndYield(items)
                        try? await Task.sleep(nanoseconds: 150_000_000)
                    }
                case "reanime":
                    var offset = 0
                    for _ in 0..<25 {
                        guard !Task.isCancelled else { break }
                        guard let raw = try? await reAnimeHarClient.search(limit: 36, offset: offset) else { break }
                        let items = ReAnimeHarClient.parseSearch(raw)
                        guard !items.isEmpty else { break }
                        appendAndYield(items)
                        if items.count < 36 { break }
                        offset += 36
                        try? await Task.sleep(nanoseconds: 150_000_000)
                    }
                default:
                    for page in 1...40 {
                        guard !Task.isCancelled else { break }
                        guard let items = try? await linkkfApi.getHome(page: page, limit: 12), !items.isEmpty else { break }
                        appendAndYield(items)
                        if items.count < 12 { break }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                continuation.finish()
            }
        }
    }

    public func searchAnime(query: String, source: String = "linkkf") async throws -> [Anime] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        switch source {
        case "miruro":
            return try await miruroClient.catalog(query: trimmed).0
        case "ohli24":
            return try await ohli24Client.catalog(query: trimmed)
        case "reanime":
            let raw = try await reAnimeHarClient.search(query: trimmed, limit: 36, offset: 0)
            return ReAnimeHarClient.parseSearch(raw)
        default:
            return try await linkkfApi.search(query: trimmed)
        }
    }

    public func getAnimeDetail(anime: Anime, source: String = "linkkf") async throws -> Anime {
        switch source {
        case "miruro":
            return try await miruroClient.detail(anime: anime)
        case "ohli24":
            return try await ohli24Client.detail(anime: anime)
        case "reanime":
            let slug = anime.detailUrl.components(separatedBy: "/anime/").last?.components(separatedBy: "/").first
                ?? anime.id.replacingOccurrences(of: "reanime:", with: "")
            let detailJson = try await reAnimeHarClient.detailData(slug: slug)
            let watchJson = (try? await reAnimeHarClient.watchData(slug: slug)) ?? ""
            return ReAnimeHarClient.parseDetailAndWatch(detailJson: detailJson, watchJson: watchJson, fallback: anime)
        default:
            if let detailed = try await linkkfApi.getAnime(postId: anime.id) {
                var merged = detailed
                if merged.description.isEmpty { merged.description = anime.description }
                return merged
            }
            return anime
        }
    }

    public func getReAnimeHomeData() async -> ([Anime], [Anime], ReAnimeHarClient.Facets) {
        let top = (try? await reAnimeHarClient.topAnime(period: "today", limit: 12)).map(ReAnimeHarClient.parseTop) ?? []
        let schedule = (try? await reAnimeHarClient.schedule(timeZone: "Asia/Seoul", week: 0)).map(ReAnimeHarClient.parseSchedule) ?? []
        let facets = (try? await reAnimeHarClient.facets()).map(ReAnimeHarClient.parseFacets) ?? ReAnimeHarClient.Facets()
        return (top, schedule, facets)
    }

    public func resolveEpisodeStream(anime: Anime, episode: Episode, source: String) async -> LinkkfApiClient.ResolvedPlayerResult {
        switch source {
        case "reanime":
            #if canImport(WebKit)
            return await ReAnimeFlixCloudBootstrapper.resolve(episode: episode, anilistId: anime.anilistId)
            #else
            return LinkkfApiClient.ResolvedPlayerResult(episodeId: episode.id, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: episode.videoUrl)
            #endif
        case "ohli24":
            return await ohli24Client.resolve(episode: episode)
        default:
            return await linkkfApi.resolvePlayer(episode: episode)
        }
    }
}
