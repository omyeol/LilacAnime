import Foundation
import SwiftUI
import Network

/// iOS port of `com.lilac.anime.viewmodel.AnimeViewModel`.
@MainActor
public final class AnimeViewModel: ObservableObject {
    public let repository = AnimeRepository()
    public let store = OfflineStore.shared

    @Published public var isOffline: Bool = false
    @Published public var downloadedIds: Set<String> = []
    @Published public var downloadProgressMap: [String: Float] = [:]

    @Published public var homeAnime: [Anime] = []
    @Published public var allAnime: [Anime] = []
    @Published public var loading: Bool = false
    @Published public var isAllAnimeLoading: Bool = false
    @Published public var error: String? = nil

    // Re:Anime state
    @Published public var reAnimeSearchResults: [Anime] = []
    @Published public var reAnimeSearchLoading: Bool = false
    @Published public var reAnimeTop: [Anime] = []
    @Published public var reAnimeSchedule: [Anime] = []
    @Published public var reAnimeFacets = ReAnimeHarClient.Facets()
    @Published public var reAnimeHomeLoading: Bool = false

    // LinkKF state
    @Published public var linkkfSchedule: [Int: [Anime]] = [:]
    @Published public var linkkfScheduleLoading: Bool = false
    @Published public var linkkfFormatTags: [LinkkfApiClient.FilterTag] = []
    @Published public var linkkfGenreTags: [LinkkfApiClient.FilterTag] = []
    @Published public var linkkfYearTags: [LinkkfApiClient.FilterTag] = []
    @Published public var linkkfFilterResults: [Anime] = []
    @Published public var linkkfFilterPage: Int = 1
    @Published public var linkkfFilterTotalPages: Int = 1
    @Published public var linkkfFilterLoading: Bool = false
    @Published public var linkkfPvTrailers: [Anime] = []
    @Published public var linkkfMovies: [Anime] = []
    @Published public var linkkf16Plus: [Anime] = []
    @Published public var linkkfHomeSectionsLoading: Bool = false
    @Published public var linkkfRelatedSeries: [LinkkfApiClient.RelatedSeries] = []

    // Settings, Library, Watch History
    @Published public var playerSettings: PlayerSettings = OfflineStore.shared.getPlayerSettings()
    @Published public var themeMode: ThemeMode = OfflineStore.shared.getThemeMode()
    @Published public var library: Set<String> = OfflineStore.shared.getLibrary()
    @Published public var watchHistory: [WatchProgress] = OfflineStore.shared.getWatchHistory()
    @Published public var sourceRevision: Int = 0

    // Detail & Episode Caches
    @Published public var detailCache: [String: Anime] = [:]
    @Published public var episodeCache: [String: [Episode]] = [:]
    @Published public var episodeLoading: [String: Bool] = [:]

    private let pathMonitor = NWPathMonitor()
    private var allAnimeTask: Task<Void, Never>?
    private var reAnimeSearchTask: Task<Void, Never>?

    public init() {
        setupNetworkMonitor()
        refreshDownloads()
        Task {
            await loadHomeAnime()
        }
    }

    private func setupNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let offline = (path.status != .satisfied)
            Task { @MainActor in
                self?.isOffline = offline
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.lilac.anime.networkmonitor"))
    }

    public func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        store.saveThemeMode(mode)
    }

    public func updatePlayerSettings(_ newSettings: PlayerSettings) {
        let sourceChanged = playerSettings.videoSourcePreference != newSettings.videoSourcePreference
        playerSettings = newSettings
        store.savePlayerSettings(newSettings)
        if sourceChanged {
            sourceRevision += 1
            homeAnime = []
            allAnime = []
            detailCache.removeAll()
            episodeCache.removeAll()
            allAnimeTask?.cancel()
            isAllAnimeLoading = false
            Task {
                await loadHomeAnime()
            }
        }
    }

    // MARK: - Home & Catalog

    public func loadHomeAnime() async {
        let source = playerSettings.videoSourcePreference
        loading = true
        error = nil

        if isOffline {
            loading = false
            return
        }

        if source == "reanime" {
            await loadReAnimeHome()
            loading = false
            return
        }

        do {
            let list = try await repository.getHomeAnimeList(source: source)
            homeAnime = Array(list.prefix(12))
            for item in list {
                detailCache[item.id] = detailCache[item.id] ?? item
            }
            if source == "linkkf" {
                Task { await loadLinkkfHomeSchedule() }
                Task { await loadLinkkfHomeSections() }
            }
        } catch {
            if homeAnime.isEmpty {
                self.error = error.localizedDescription
            }
        }
        loading = false
    }

    public func loadLinkkfHomeSchedule(force: Bool = false) async {
        guard !linkkfScheduleLoading else { return }
        if !force && !linkkfSchedule.isEmpty { return }
        linkkfScheduleLoading = true
        let ids = [21189, 21190, 21191, 21192, 21193, 21194, 21195]
        var loaded: [Int: [Anime]] = [:]
        for id in ids {
            if let list = try? await repository.linkkfApi.getSchedule(categoryTagId: id, limit: 50) {
                loaded[id] = list
            }
        }
        linkkfSchedule = loaded
        linkkfScheduleLoading = false
    }

    public func loadLinkkfHomeSections(force: Bool = false) async {
        guard !linkkfHomeSectionsLoading else { return }
        if !force && (!linkkfPvTrailers.isEmpty || !linkkfMovies.isEmpty || !linkkf16Plus.isEmpty) { return }
        linkkfHomeSectionsLoading = true
        linkkfPvTrailers = (try? await repository.linkkfApi.getSeasonType(tagId: 5086, limit: 8)) ?? []
        linkkfMovies = (try? await repository.linkkfApi.getSeasonType(tagId: 5061, limit: 8)) ?? []
        linkkf16Plus = (try? await repository.linkkfApi.getSeasonType(tagId: 5085, limit: 8)) ?? []
        linkkfHomeSectionsLoading = false
    }

    public func loadLinkkfFilterTags() async {
        guard linkkfFormatTags.isEmpty && linkkfGenreTags.isEmpty && linkkfYearTags.isEmpty else { return }
        linkkfFormatTags = (try? await repository.linkkfApi.getFilterTags(taxonomy: "anime-seasontype")) ?? []
        linkkfGenreTags = (try? await repository.linkkfApi.getFilterTags(taxonomy: "anigenres")) ?? []
        linkkfYearTags = ((try? await repository.linkkfApi.getFilterTags(taxonomy: "anime-seasonys")) ?? []).reversed()
    }

    public func loadLinkkfFilteredAnime(
        page: Int = 1,
        formatIds: [Int] = [],
        genreIds: [Int] = [],
        yearIds: [Int] = []
    ) async {
        guard !linkkfFilterLoading else { return }
        linkkfFilterLoading = true
        if let res = try? await repository.linkkfApi.getFilteredAnime(
            page: page,
            limit: 40,
            seasonTypeIds: formatIds,
            genreIds: genreIds,
            yearIds: yearIds
        ) {
            linkkfFilterResults = res.items
            linkkfFilterPage = res.page
            linkkfFilterTotalPages = res.totalPages
        } else {
            linkkfFilterResults = []
        }
        linkkfFilterLoading = false
    }

    public func loadReAnimeHome() async {
        guard !reAnimeHomeLoading else { return }
        reAnimeHomeLoading = true
        let (top, schedule, facets) = await repository.getReAnimeHomeData()
        reAnimeTop = top
        reAnimeSchedule = schedule
        reAnimeFacets = facets
        homeAnime = top.isEmpty ? schedule : top
        for item in (top + schedule) {
            detailCache[item.id] = detailCache[item.id] ?? item
        }
        reAnimeHomeLoading = false
    }

    public func loadAllAnime(forceRefresh: Bool = false) {
        let source = playerSettings.videoSourcePreference
        if !forceRefresh && isAllAnimeLoading { return }
        allAnimeTask?.cancel()

        let cached = store.getSavedAnimeList(source: source)
        if !cached.isEmpty {
            allAnime = cached
            if !forceRefresh { return }
        }

        isAllAnimeLoading = true
        allAnimeTask = Task {
            var latest: [Anime] = []
            for await pageList in repository.getAllAnimeListStream(source: source) {
                if Task.isCancelled { break }
                latest = pageList
                self.allAnime = pageList
            }
            if !latest.isEmpty {
                store.saveAnimeList(latest, source: source, markFresh: true)
            }
            self.isAllAnimeLoading = false
        }
    }

    public func searchReAnime(
        query: String,
        genre: String = "",
        year: Int? = nil,
        season: String = "",
        status: String = "",
        format: String = ""
    ) {
        reAnimeSearchTask?.cancel()
        reAnimeSearchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            reAnimeSearchLoading = true
            let raw = (try? await repository.reAnimeHarClient.search(
                query: query,
                limit: 36,
                offset: 0,
                genre: genre.isEmpty ? [] : [genre],
                year: year,
                season: season.isEmpty ? nil : season,
                status: status.isEmpty ? nil : status,
                format: format.isEmpty ? nil : format
            )) ?? ""
            let results = ReAnimeHarClient.parseSearch(raw)
            if !Task.isCancelled {
                reAnimeSearchResults = results
                for item in results {
                    detailCache[item.id] = detailCache[item.id] ?? item
                }
                reAnimeSearchLoading = false
            }
        }
    }

    // MARK: - Detail & Episodes

    public func getAnime(id: String) -> Anime? {
        if let d = detailCache[id] { return d }
        if let found = (homeAnime + allAnime + reAnimeTop + reAnimeSchedule + reAnimeSearchResults).first(where: { $0.id == id }) {
            return found
        }
        return store.getAnime(id: id)
    }

    public func loadAnimeDetail(_ anime: Anime, force: Bool = false) async -> Anime {
        if !force, let cached = detailCache[anime.id], !cached.episodes.isEmpty {
            return cached
        }
        episodeLoading[anime.id] = true
        defer { episodeLoading[anime.id] = false }

        do {
            let detailed = try await repository.getAnimeDetail(anime: anime, source: playerSettings.videoSourcePreference)
            detailCache[anime.id] = detailed
            episodeCache[anime.id] = detailed.episodes
            store.saveAnime(detailed)
            if playerSettings.videoSourcePreference == "linkkf" {
                linkkfRelatedSeries = (try? await repository.linkkfApi.getRelatedSeries(currentPostId: anime.id)) ?? []
            }
            return detailed
        } catch {
            if let offline = store.getAnime(id: anime.id) {
                detailCache[anime.id] = offline
                episodeCache[anime.id] = offline.episodes
                return offline
            }
            return anime
        }
    }

    // MARK: - Library & Watch History

    public func isInLibrary(_ animeId: String) -> Bool {
        library.contains(animeId)
    }

    public func toggleLibrary(_ anime: Anime) {
        if library.contains(anime.id) {
            library.remove(anime.id)
        } else {
            library.insert(anime.id)
            store.saveAnime(anime)
        }
        store.saveLibrary(library)
    }

    public func updateWatchProgress(anime: Anime, episode: Episode, progress: Float) {
        let clamped = max(0.0, min(1.0, progress))
        var current = watchHistory
        let entry = WatchProgress(
            animeId: anime.id,
            episodeNumber: episode.number,
            progress: clamped,
            episodeKey: episode.displayNumber
        )
        current.removeAll { $0.animeId == anime.id && ($0.episodeKey == episode.displayNumber || $0.episodeNumber == episode.number) }
        current.insert(entry, at: 0)
        watchHistory = current
        store.saveWatchHistory(current)
        store.saveAnime(anime)
    }

    public func removeWatchHistory(animeId: String) {
        watchHistory.removeAll { $0.animeId == animeId }
        store.saveWatchHistory(watchHistory)
    }

    public func clearAllWatchHistory() {
        watchHistory.removeAll()
        store.saveWatchHistory([])
    }

    // MARK: - Offline Downloads

    public func refreshDownloads() {
        let statuses = store.listDownloadStatuses()
        var ids = Set<String>()
        var prog: [String: Float] = [:]
        for st in statuses {
            if st.state == "completed" {
                ids.insert(st.id)
            } else if st.state == "downloading" || st.state == "queued" {
                prog[st.id] = st.progress
            }
        }
        downloadedIds = ids
        downloadProgressMap = prog
    }

    public func isEpisodeDownloaded(animeId: String, episode: Episode) -> Bool {
        store.completedPathForEpisode(animeId: animeId, episodeId: episode.id, episodeNumber: episode.number) != nil
    }

    public func downloadEpisode(anime: Anime, episode: Episode) {
        let statusId = "\(anime.id)::\(episode.id)"
        store.saveAnime(anime)
        store.updateDownloadStatus(OfflineStore.DownloadStatus(
            id: statusId,
            animeId: anime.id,
            episodeId: episode.id,
            episodeNumber: episode.number,
            title: "\(anime.title) \(episode.displayNumber)화",
            state: "downloading",
            progress: 0.05,
            localPath: nil,
            updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
        ))
        refreshDownloads()

        Task {
            let resolved = await repository.resolveEpisodeStream(
                anime: anime,
                episode: episode,
                source: playerSettings.videoSourcePreference
            )
            // Also cache subtitle if available
            if let subUrl = resolved.subtitleUrl, !subUrl.isEmpty {
                let opt = SubtitleDiscoveryService.SubtitleOption(
                    source: playerSettings.videoSourcePreference,
                    name: "\(anime.title) \(episode.displayNumber)화 기본 자막",
                    url: subUrl,
                    format: "vtt"
                )
                _ = await SubtitleDiscoveryService.shared.downloadSubtitle(
                    option: opt,
                    animeId: anime.id,
                    episodeKey: episode.displayNumber,
                    referer: resolved.subtitleReferer
                )
            }

            let outDir = store.rootDirectory.appendingPathComponent("videos", isDirectory: true)
            try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            let manifestPath = outDir.appendingPathComponent("\(OfflineStore.safeFilename(statusId)).m3u8url")
            if let stream = resolved.m3u8Url {
                try? stream.write(to: manifestPath, atomically: true, encoding: .utf8)
                store.updateDownloadStatus(OfflineStore.DownloadStatus(
                    id: statusId,
                    animeId: anime.id,
                    episodeId: episode.id,
                    episodeNumber: episode.number,
                    title: "\(anime.title) \(episode.displayNumber)화",
                    state: "completed",
                    progress: 1.0,
                    localPath: manifestPath.path,
                    updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
                ))
            } else {
                store.updateDownloadStatus(OfflineStore.DownloadStatus(
                    id: statusId,
                    animeId: anime.id,
                    episodeId: episode.id,
                    episodeNumber: episode.number,
                    title: "\(anime.title) \(episode.displayNumber)화",
                    state: "failed",
                    progress: 0.0,
                    localPath: nil,
                    updatedAt: Int64(Date().timeIntervalSince1970 * 1000)
                ))
            }
            refreshDownloads()
        }
    }
}
