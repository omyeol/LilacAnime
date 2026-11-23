import Foundation

public struct Anime: Identifiable, Codable, Hashable, Sendable {
    public var id: String = ""
    public var anilistId: Int? = nil
    public var malId: Int? = nil
    public var title: String = ""
    public var poster: String = ""
    public var backdrop: String = ""
    public var genres: [String] = []
    public var description: String = ""
    public var airedDate: String = ""
    public var year: String = ""
    public var season: String = ""
    public var seasonYear: Int? = nil
    public var seasonNumber: Int? = nil
    public var format: String = ""
    public var studios: [String] = []
    public var source: String = ""
    public var romaji: String = ""
    public var english: String = ""
    public var native: String = ""
    public var synonyms: String = ""
    public var note: String = ""
    public var seasonTypeTagIds: [Int] = []
    public var studioTagIds: [Int] = []
    public var sourceTagIds: [Int] = []
    public var yearTagId: Int? = nil
    public var seriesTagIds: [Int] = []
    public var detailUrl: String = ""
    public var episodes: [Episode] = []
    public var dubEpisodes: [Episode] = []
    public var reAnimeRelated: [ReAnimeRelated] = []

    public init(
        id: String = "",
        anilistId: Int? = nil,
        malId: Int? = nil,
        title: String = "",
        poster: String = "",
        backdrop: String = "",
        genres: [String] = [],
        description: String = "",
        airedDate: String = "",
        year: String = "",
        season: String = "",
        seasonYear: Int? = nil,
        seasonNumber: Int? = nil,
        format: String = "",
        studios: [String] = [],
        source: String = "",
        romaji: String = "",
        english: String = "",
        native: String = "",
        synonyms: String = "",
        note: String = "",
        seasonTypeTagIds: [Int] = [],
        studioTagIds: [Int] = [],
        sourceTagIds: [Int] = [],
        yearTagId: Int? = nil,
        seriesTagIds: [Int] = [],
        detailUrl: String = "",
        episodes: [Episode] = [],
        dubEpisodes: [Episode] = [],
        reAnimeRelated: [ReAnimeRelated] = []
    ) {
        self.id = id
        self.anilistId = anilistId
        self.malId = malId
        self.title = title
        self.poster = poster
        self.backdrop = backdrop
        self.genres = genres
        self.description = description
        self.airedDate = airedDate
        self.year = year
        self.season = season
        self.seasonYear = seasonYear
        self.seasonNumber = seasonNumber
        self.format = format
        self.studios = studios
        self.source = source
        self.romaji = romaji
        self.english = english
        self.native = native
        self.synonyms = synonyms
        self.note = note
        self.seasonTypeTagIds = seasonTypeTagIds
        self.studioTagIds = studioTagIds
        self.sourceTagIds = sourceTagIds
        self.yearTagId = yearTagId
        self.seriesTagIds = seriesTagIds
        self.detailUrl = detailUrl
        self.episodes = episodes
        self.dubEpisodes = dubEpisodes
        self.reAnimeRelated = reAnimeRelated
    }
}

public struct ReAnimeRelated: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var nativeTitle: String = ""
    public var romaji: String = ""
    public var poster: String = ""
    public var format: String = ""
    public var relationType: String = ""
    public var season: String = ""
    public var seasonYear: Int? = nil

    public init(
        id: String,
        title: String,
        nativeTitle: String = "",
        romaji: String = "",
        poster: String = "",
        format: String = "",
        relationType: String = "",
        season: String = "",
        seasonYear: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.nativeTitle = nativeTitle
        self.romaji = romaji
        self.poster = poster
        self.format = format
        self.relationType = relationType
        self.season = season
        self.seasonYear = seasonYear
    }
}

public struct Episode: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var number: Int
    public var title: String
    public var description: String = ""
    public var videoUrl: String? = nil
    public var vttUrl: String? = nil
    public var displayNumber: String
    public var nativeTitle: String = ""
    public var airedDate: String = ""
    public var isFiller: Bool = false
    public var isRecap: Bool = false
    public var playable: Bool = true
    public var subbed: Bool = false
    public var dubbed: Bool = false
    public var thumbnailUrl: String = ""

    public init(
        id: String,
        number: Int,
        title: String,
        description: String = "",
        videoUrl: String? = nil,
        vttUrl: String? = nil,
        displayNumber: String? = nil,
        nativeTitle: String = "",
        airedDate: String = "",
        isFiller: Bool = false,
        isRecap: Bool = false,
        playable: Bool = true,
        subbed: Bool = false,
        dubbed: Bool = false,
        thumbnailUrl: String = ""
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.description = description
        self.videoUrl = videoUrl
        self.vttUrl = vttUrl
        self.displayNumber = displayNumber ?? String(number)
        self.nativeTitle = nativeTitle
        self.airedDate = airedDate
        self.isFiller = isFiller
        self.isRecap = isRecap
        self.playable = playable
        self.subbed = subbed
        self.dubbed = dubbed
        self.thumbnailUrl = thumbnailUrl
    }
}

public struct WatchProgress: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(animeId)::\(episodeKey)" }
    public var animeId: String
    public var episodeNumber: Int
    public var progress: Float
    public var episodeKey: String
    public var updatedAt: Int64

    public init(
        animeId: String,
        episodeNumber: Int,
        progress: Float,
        episodeKey: String? = nil,
        updatedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.animeId = animeId
        self.episodeNumber = episodeNumber
        self.progress = progress
        self.episodeKey = episodeKey ?? String(episodeNumber)
        self.updatedAt = updatedAt
    }
}
