import SwiftUI
import AVKit
import UniformTypeIdentifiers

/// iOS port of `DetailScreen.kt` and `DetailComponents.kt`.
public struct DetailScreen: View {
    @ObservedObject public var vm: AnimeViewModel
    public let initialAnime: Anime
    public let onPlayEpisode: (Anime, Episode) -> Void
    public let onSelectRelated: (Anime) -> Void

    @State private var anime: Anime
    @State private var isLoading: Bool = false
    @State private var episodeSortAscending: Bool = true
    @State private var selectedPage: Int = 0
    private let pageSize = 50

    public init(
        vm: AnimeViewModel,
        initialAnime: Anime,
        onPlayEpisode: @escaping (Anime, Episode) -> Void,
        onSelectRelated: @escaping (Anime) -> Void
    ) {
        self.vm = vm
        self.initialAnime = initialAnime
        self.onPlayEpisode = onPlayEpisode
        self.onSelectRelated = onSelectRelated
        self._anime = State(initialValue: initialAnime)
    }

    private var sortedEpisodes: [Episode] {
        let list = anime.episodes
        return episodeSortAscending ? list : list.reversed()
    }

    private var pagedEpisodes: [Episode] {
        let list = sortedEpisodes
        guard list.count > pageSize else { return list }
        let start = min(selectedPage * pageSize, list.count)
        let end = min(start + pageSize, list.count)
        return Array(list[start..<end])
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Backdrop & Poster
                ZStack(alignment: .bottomLeading) {
                    LilacRemoteImage(url: anime.backdrop.isEmpty ? anime.poster : anime.backdrop)
                        .frame(height: 240)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [.black.opacity(0.2), .black.opacity(0.88)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    HStack(alignment: .bottom, spacing: 16) {
                        LilacRemoteImage(url: anime.poster)
                            .frame(width: 105, height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(radius: 8)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(anime.title)
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                                .lineLimit(3)

                            if !anime.native.isEmpty {
                                Text(anime.native)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .lineLimit(1)
                            }

                            HStack(spacing: 8) {
                                if !anime.year.isEmpty {
                                    badge(anime.year)
                                }
                                if !anime.format.isEmpty {
                                    badge(anime.format)
                                }
                                if let aid = anime.anilistId {
                                    badge("AL #\(aid)")
                                }
                            }
                        }
                    }
                    .padding(20)
                }

                // Action Buttons (Play / Resume & Bookmark)
                HStack(spacing: 12) {
                    Button {
                        if let targetEp = resumeEpisode ?? anime.episodes.first {
                            onPlayEpisode(anime, targetEp)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "play.fill")
                            if let resume = resumeEpisode {
                                Text("\(resume.displayNumber)화 이어보기")
                                    .fontWeight(.semibold)
                            } else {
                                Text("1화부터 재생")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.purple)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(anime.episodes.isEmpty)

                    Button {
                        vm.toggleLibrary(anime)
                    } label: {
                        Image(systemName: vm.isInLibrary(anime.id) ? "heart.fill" : "heart")
                            .font(.title3)
                            .padding(13)
                            .background(Color.secondary.opacity(0.15))
                            .foregroundStyle(vm.isInLibrary(anime.id) ? .pink : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)

                // Genres & Studios
                if !anime.genres.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(anime.genres, id: \.self) { g in
                                Text(g)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.purple.opacity(0.14))
                                    .foregroundStyle(.purple)
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                // Synopsis
                if !anime.description.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("줄거리")
                            .font(.headline)
                        Text(anime.description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                }

                // Episode Header & Pagination (Re:Anime / LinkKF)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("회차 목록 (\(anime.episodes.count))")
                            .font(.headline)
                        Spacer()
                        Button {
                            episodeSortAscending.toggle()
                        } label: {
                            Label(episodeSortAscending ? "1화부터" : "최신화부터", systemImage: "arrow.up.arrow.down")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 20)

                    if anime.episodes.count > pageSize {
                        let pageCount = (anime.episodes.count + pageSize - 1) / pageSize
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(0..<pageCount, id: \.self) { p in
                                    let startNum = p * pageSize + 1
                                    let endNum = min((p + 1) * pageSize, anime.episodes.count)
                                    Button("\(startNum)~\(endNum)") {
                                        selectedPage = p
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedPage == p ? Color.purple : Color.secondary.opacity(0.14))
                                    .foregroundStyle(selectedPage == p ? .white : .primary)
                                    .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    if isLoading && anime.episodes.isEmpty {
                        ProgressView("회차 정보를 불러오는 중...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if anime.episodes.isEmpty {
                        Text("표시할 회차가 없습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 20)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(pagedEpisodes) { ep in
                                episodeRow(ep)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }

                // Re:Anime Related Works
                if !anime.reAnimeRelated.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("연관 작품")
                            .font(.headline)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(anime.reAnimeRelated) { rel in
                                    Button {
                                        let seed = Anime(
                                            id: rel.id,
                                            title: rel.title,
                                            poster: rel.poster,
                                            backdrop: rel.poster,
                                            format: rel.format,
                                            source: "reanime",
                                            romaji: rel.romaji,
                                            native: rel.nativeTitle,
                                            note: rel.relationType
                                        )
                                        onSelectRelated(seed)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            LilacRemoteImage(url: rel.poster)
                                                .frame(width: 115, height: 162)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                            Text(rel.relationType)
                                                .font(.caption2.bold())
                                                .foregroundStyle(.purple)
                                            Text(rel.title)
                                                .font(.caption)
                                                .lineLimit(2)
                                                .frame(width: 115, alignment: .leading)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .navigationTitle(anime.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: initialAnime.id) {
            isLoading = true
            let loaded = await vm.loadAnimeDetail(initialAnime)
            self.anime = loaded
            isLoading = false
        }
    }

    private var resumeEpisode: Episode? {
        guard let history = vm.watchHistory.first(where: { $0.animeId == anime.id }) else { return nil }
        return anime.episodes.first(where: { $0.displayNumber == history.episodeKey || $0.number == history.episodeNumber })
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(0.2))
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }

    private func episodeRow(_ ep: Episode) -> some View {
        let watched = vm.watchHistory.first(where: { $0.animeId == anime.id && ($0.episodeKey == ep.displayNumber || $0.episodeNumber == ep.number) })
        let downloaded = vm.isEpisodeDownloaded(animeId: anime.id, episode: ep)

        return HStack(spacing: 12) {
            Button {
                onPlayEpisode(anime, ep)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Text(ep.displayNumber)
                            .font(.subheadline.bold())
                            .foregroundStyle(.purple)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(ep.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if ep.isFiller {
                                Text("Filler")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }

                        if !ep.airedDate.isEmpty {
                            Text(ep.airedDate)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        if let watched {
                            ProgressView(value: Double(watched.progress))
                                .tint(.purple)
                        }
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            // Offline Download Button
            Button {
                if downloaded {
                    vm.store.removeDownload(animeId: anime.id, episode: ep)
                    vm.refreshDownloads()
                } else {
                    vm.downloadEpisode(anime: anime, episode: ep)
                }
            } label: {
                Image(systemName: downloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(downloaded ? .green : .secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
