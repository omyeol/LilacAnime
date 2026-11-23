import SwiftUI

/// iOS port of `MainActivity.kt` and `AppNavigation.kt`.
@main
public struct LilacAnimeApp: App {
    @StateObject private var vm = AnimeViewModel()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            LilacRootView(vm: vm)
                .preferredColorScheme(preferredScheme)
        }
    }

    private var preferredScheme: ColorScheme? {
        switch vm.themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

public struct ActivePlaybackItem: Identifiable, Hashable {
    public var id: String { "\(anime.id)::\(episode.id)" }
    public let anime: Anime
    public let episode: Episode
}

public struct LilacRootView: View {
    @ObservedObject public var vm: AnimeViewModel
    @State private var selectedTab: Int = 0
    @State private var navigationPath: [Anime] = []
    @State private var activePlayback: ActivePlaybackItem? = nil

    public init(vm: AnimeViewModel) {
        self.vm = vm
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $navigationPath) {
                HomeScreen(
                    vm: vm,
                    onOpenDetail: { anime in navigationPath.append(anime) },
                    onNavigateTab: { tab in selectedTab = tab }
                )
                .navigationDestination(for: Anime.self) { anime in
                    DetailScreen(
                        vm: vm,
                        initialAnime: anime,
                        onPlayEpisode: { targetAnime, ep in
                            activePlayback = ActivePlaybackItem(anime: targetAnime, episode: ep)
                        },
                        onSelectRelated: { related in
                            navigationPath.append(related)
                        }
                    )
                }
            }
            .tabItem {
                Label("홈", systemImage: "house.fill")
            }
            .tag(0)

            NavigationStack {
                AllAnimeScreen(
                    vm: vm,
                    onOpenDetail: { anime in
                        selectedTab = 0
                        navigationPath.append(anime)
                    }
                )
            }
            .tabItem {
                Label("전체", systemImage: "square.grid.2x2.fill")
            }
            .tag(1)

            NavigationStack {
                SearchScreen(
                    vm: vm,
                    onOpenDetail: { anime in
                        selectedTab = 0
                        navigationPath.append(anime)
                    }
                )
            }
            .tabItem {
                Label("검색", systemImage: "magnifyingglass")
            }
            .tag(2)

            NavigationStack {
                LibraryScreen(
                    vm: vm,
                    onOpenDetail: { anime in
                        selectedTab = 0
                        navigationPath.append(anime)
                    }
                )
            }
            .tabItem {
                Label("보관함", systemImage: "books.vertical.fill")
            }
            .tag(3)

            SettingsScreen(vm: vm)
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(.purple)
        .fullScreenCover(item: $activePlayback) { item in
            PlayerScreen(
                vm: vm,
                anime: item.anime,
                episode: item.episode,
                onDismiss: {
                    activePlayback = nil
                }
            )
        }
    }
}
