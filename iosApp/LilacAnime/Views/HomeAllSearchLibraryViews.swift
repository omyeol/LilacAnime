import SwiftUI

/// iOS port of `HomeScreen.kt` and `ContinueWatchingRail.kt`.
public struct HomeScreen: View {
    @ObservedObject public var vm: AnimeViewModel
    public let onOpenDetail: (Anime) -> Void
    public let onNavigateTab: (Int) -> Void

    @State private var scheduleTab: Int = 0
    private let scheduleTabs = ["UP", "월", "화", "수", "목", "금", "토", "일"]

    private var source: String { vm.playerSettings.videoSourcePreference }
    private var isLinkkf: Bool { source == "linkkf" }
    private var isReAnime: Bool { source == "reanime" }
    private var heroPool: [Anime] {
        if isReAnime {
            return vm.reAnimeTop.isEmpty ? vm.reAnimeSchedule : vm.reAnimeTop
        }
        return vm.homeAnime
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ScreenHeader(title: "오늘은 무엇을 볼까요?", subtitle: "LilacAnime iOS · \(source.uppercased())") {
                    Button {
                        onNavigateTab(2) // Search tab
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title3)
                            .padding(8)
                            .background(Color.purple.opacity(0.14))
                            .clipShape(Circle())
                    }
                }

                // Hero Banner
                if (vm.loading || vm.reAnimeHomeLoading) && heroPool.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("작품을 불러오는 중이에요")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                } else if let err = vm.error, heroPool.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("다시 시도") {
                            Task { await vm.loadHomeAnime() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                } else if let first = heroPool.first {
                    HeroCardView(anime: first, onOpen: onOpenDetail)
                }

                // Continue Watching Rail
                if !vm.watchHistory.isEmpty {
                    continueWatchingSection
                }

                // LinkKF Schedule & Categories
                if isLinkkf {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("방영 일정")
                            .font(.headline)
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(scheduleTabs.indices, id: \.self) { idx in
                                    Button {
                                        scheduleTab = idx
                                    } label: {
                                        Text(scheduleTabs[idx])
                                            .font(.subheadline.weight(.medium))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                            .background(scheduleTab == idx ? Color.purple : Color.secondary.opacity(0.15))
                                            .foregroundStyle(scheduleTab == idx ? .white : .primary)
                                            .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }

                        let scheduleItems = scheduleTab == 0
                            ? vm.homeAnime
                            : (vm.linkkfSchedule[21188 + scheduleTab] ?? [])

                        if vm.linkkfScheduleLoading && scheduleItems.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else if !scheduleItems.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 12) {
                                    ForEach(scheduleItems.prefix(20)) { anime in
                                        AnimeCardView(anime: anime, onOpen: onOpenDetail)
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                        } else {
                            Text("이 요일에 방영하는 작품이 없어요.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 20)
                        }
                    }

                    if !vm.linkkfPvTrailers.isEmpty {
                        AnimeRailView(title: "인기 급상승 · 트레일러", items: vm.linkkfPvTrailers, onOpen: onOpenDetail)
                    }
                    if !vm.linkkfMovies.isEmpty {
                        AnimeRailView(title: "극장판", items: vm.linkkfMovies, onOpen: onOpenDetail)
                    }
                    if !vm.linkkf16Plus.isEmpty {
                        AnimeRailView(title: "16+ 애니", items: vm.linkkf16Plus, onOpen: onOpenDetail)
                    }
                }

                // Re:Anime Rails
                if isReAnime {
                    if !vm.reAnimeTop.isEmpty {
                        AnimeRailView(title: "오늘의 인기", items: Array(vm.reAnimeTop.prefix(12)), onOpen: onOpenDetail)
                    }
                    if !vm.reAnimeSchedule.isEmpty {
                        AnimeRailView(title: "이번 주 방영", items: Array(vm.reAnimeSchedule.prefix(12)), onOpen: onOpenDetail)
                    }
                }

                // Default Latest Update Rail
                if !isReAnime && !vm.homeAnime.isEmpty {
                    AnimeRailView(title: "최신 업데이트", items: vm.homeAnime, onOpen: onOpenDetail)
                }
            }
            .padding(.bottom, 28)
        }
        .refreshable {
            await vm.loadHomeAnime()
        }
    }

    private var continueWatchingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("이어보기")
                .font(.headline)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(vm.watchHistory.prefix(12)) { entry in
                        if let anime = vm.getAnime(id: entry.animeId) {
                            Button {
                                onOpenDetail(anime)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack(alignment: .bottomLeading) {
                                        LilacRemoteImage(url: anime.backdrop.isEmpty ? anime.poster : anime.backdrop)
                                            .frame(width: 200, height: 112)
                                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(entry.episodeKey)화 시청 중")
                                                .font(.caption.bold())
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(.black.opacity(0.65))
                                                .clipShape(Capsule())

                                            ProgressView(value: Double(entry.progress))
                                                .tint(.purple)
                                        }
                                        .padding(8)
                                    }
                                    Text(anime.title)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .frame(width: 200, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }
}

/// iOS port of `AllAnimeScreen.kt`.
public struct AllAnimeScreen: View {
    @ObservedObject public var vm: AnimeViewModel
    public let onOpenDetail: (Anime) -> Void

    @State private var selectedGenreId: Int? = nil
    @State private var selectedYearId: Int? = nil
    @State private var selectedFormatId: Int? = nil

    private let columns = [
        GridItem(.adaptive(minimum: 115), spacing: 14)
    ]

    public var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "전체 작품", subtitle: "\(displayedAnime.count)개 작품") {
                Button {
                    vm.loadAllAnime(forceRefresh: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                }
            }

            if vm.playerSettings.videoSourcePreference == "linkkf" && !vm.linkkfGenreTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            selectedGenreId = nil
                        } label: {
                            Text("전체 장르")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selectedGenreId == nil ? Color.purple : Color.secondary.opacity(0.15))
                                .foregroundStyle(selectedGenreId == nil ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        ForEach(vm.linkkfGenreTags.prefix(20)) { tag in
                            Button {
                                selectedGenreId = tag.id
                                Task {
                                    await vm.loadLinkkfFilteredAnime(
                                        page: 1,
                                        formatIds: selectedFormatId.map { [$0] } ?? [],
                                        genreIds: [tag.id],
                                        yearIds: selectedYearId.map { [$0] } ?? []
                                    )
                                }
                            } label: {
                                Text(tag.name)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedGenreId == tag.id ? Color.purple : Color.secondary.opacity(0.15))
                                    .foregroundStyle(selectedGenreId == tag.id ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }

            ScrollView {
                if vm.isAllAnimeLoading && displayedAnime.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("전체 카탈로그를 동기화하는 중...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(displayedAnime) { anime in
                            AnimeCardView(anime: anime, width: 115, onOpen: onOpenDetail)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
        .onAppear {
            if vm.allAnime.isEmpty {
                vm.loadAllAnime()
            }
            if vm.playerSettings.videoSourcePreference == "linkkf" {
                Task { await vm.loadLinkkfFilterTags() }
            }
        }
    }

    private var displayedAnime: [Anime] {
        if selectedGenreId != nil && !vm.linkkfFilterResults.isEmpty {
            return vm.linkkfFilterResults
        }
        return vm.allAnime.isEmpty ? vm.homeAnime : vm.allAnime
    }
}

/// iOS port of `SearchScreen.kt` and `ReAnimeUi.kt`.
public struct SearchScreen: View {
    @ObservedObject public var vm: AnimeViewModel
    public let onOpenDetail: (Anime) -> Void

    @State private var query: String = ""
    @State private var searchResults: [Anime] = []
    @State private var isSearching: Bool = false
    @State private var selectedGenre: String = ""
    @State private var selectedSeason: String = ""

    private let columns = [
        GridItem(.adaptive(minimum: 115), spacing: 14)
    ]

    public var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "애니메이션 검색", subtitle: "제목 · 원제 · 로마자 검색") {
                EmptyView()
            }

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("작품 제목을 입력하세요...", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        triggerSearch()
                    }
                if !query.isEmpty {
                    Button {
                        query = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 20)

            // Re:Anime Facet Filters
            if vm.playerSettings.videoSourcePreference == "reanime" && !vm.reAnimeFacets.genres.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button("전체") {
                            selectedGenre = ""
                            triggerSearch()
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selectedGenre.isEmpty ? Color.purple : Color.secondary.opacity(0.15))
                        .foregroundStyle(selectedGenre.isEmpty ? .white : .primary)
                        .clipShape(Capsule())

                        ForEach(vm.reAnimeFacets.genres.prefix(15), id: \.self) { g in
                            Button(g) {
                                selectedGenre = g
                                triggerSearch()
                            }
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedGenre == g ? Color.purple : Color.secondary.opacity(0.15))
                            .foregroundStyle(selectedGenre == g ? .white : .primary)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }

            ScrollView {
                if isSearching || vm.reAnimeSearchLoading {
                    ProgressView("검색 중...")
                        .padding(.top, 60)
                } else if activeResults.isEmpty && !query.isEmpty {
                    Text("'\(query)'에 대한 검색 결과가 없습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(activeResults) { anime in
                            AnimeCardView(anime: anime, width: 115, onOpen: onOpenDetail)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
        }
        .onChange(of: query) { _, _ in
            triggerSearch()
        }
    }

    private var activeResults: [Anime] {
        if vm.playerSettings.videoSourcePreference == "reanime" {
            return query.isEmpty && selectedGenre.isEmpty ? vm.reAnimeTop : vm.reAnimeSearchResults
        }
        return query.isEmpty ? vm.homeAnime : searchResults
    }

    private func triggerSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if vm.playerSettings.videoSourcePreference == "reanime" {
            vm.searchReAnime(query: trimmed, genre: selectedGenre, season: selectedSeason)
            return
        }
        guard !trimmed.isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        Task {
            let found = (try? await vm.repository.searchAnime(query: trimmed, source: vm.playerSettings.videoSourcePreference)) ?? []
            await MainActor.run {
                self.searchResults = found
                self.isSearching = false
            }
        }
    }
}

/// iOS port of `LibraryScreen.kt` and `WatchHistoryScreen.kt`.
public struct LibraryScreen: View {
    @ObservedObject public var vm: AnimeViewModel
    public let onOpenDetail: (Anime) -> Void

    @State private var selectedSegment: Int = 0 // 0: 보관함, 1: 시청 기록, 2: 오프라인 다운로드

    private let columns = [
        GridItem(.adaptive(minimum: 115), spacing: 14)
    ]

    public var body: some View {
        VStack(spacing: 12) {
            ScreenHeader(title: "보관함", subtitle: "찜한 작품 · 시청 기록 · 오프라인 저장") {
                if selectedSegment == 1 && !vm.watchHistory.isEmpty {
                    Button("기록 비우기", role: .destructive) {
                        vm.clearAllWatchHistory()
                    }
                    .font(.caption)
                }
            }

            Picker("구분", selection: $selectedSegment) {
                Text("찜한 작품 (\(vm.library.count))").tag(0)
                Text("시청 기록 (\(vm.watchHistory.count))").tag(1)
                Text("다운로드 (\(vm.downloadedIds.count))").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            ScrollView {
                switch selectedSegment {
                case 0:
                    let items = vm.library.compactMap { vm.getAnime(id: $0) }
                    if items.isEmpty {
                        emptyMessage("보관함에 추가한 작품이 없습니다.")
                    } else {
                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(items) { anime in
                                AnimeCardView(anime: anime, width: 115, onOpen: onOpenDetail)
                            }
                        }
                        .padding(20)
                    }
                case 1:
                    if vm.watchHistory.isEmpty {
                        emptyMessage("최근 시청한 애니메이션 기록이 없습니다.")
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(vm.watchHistory) { item in
                                if let anime = vm.getAnime(id: item.animeId) {
                                    HStack(spacing: 14) {
                                        LilacRemoteImage(url: anime.poster)
                                            .frame(width: 64, height: 90)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(anime.title)
                                                .font(.subheadline.bold())
                                                .lineLimit(2)
                                            Text("\(item.episodeKey)화 · \(Int(item.progress * 100))% 시청")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            ProgressView(value: Double(item.progress))
                                                .tint(.purple)
                                        }
                                        Spacer()
                                        Button {
                                            vm.removeWatchHistory(animeId: anime.id)
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.secondary.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                                    .onTapGesture {
                                        onOpenDetail(anime)
                                    }
                                }
                            }
                        }
                        .padding(20)
                    }
                default:
                    let statuses = vm.store.listDownloadStatuses()
                    if statuses.isEmpty {
                        emptyMessage("오프라인으로 저장된 회차가 없습니다.")
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(statuses) { st in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(st.title)
                                            .font(.subheadline.weight(.medium))
                                        Text(st.state == "completed" ? "오프라인 재생 가능" : "상태: \(st.state)")
                                            .font(.caption)
                                            .foregroundStyle(st.state == "completed" ? .green : .secondary)
                                    }
                                    Spacer()
                                    if let anime = vm.getAnime(id: st.animeId) {
                                        Button("열기") {
                                            onOpenDetail(anime)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(12)
                                .background(Color.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(20)
                    }
                }
            }
        }
    }

    private func emptyMessage(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 80)
    }
}
