import SwiftUI

/// iOS port of `Color.kt`, `Theme.kt`, and `LilacComponents.kt`.
public enum LilacPalette {
    // Light
    public static let lightPrimary = Color(red: 0x6D / 255.0, green: 0x4C / 255.0, blue: 0x9F / 255.0)
    public static let lightPrimaryContainer = Color(red: 0xEB / 255.0, green: 0xDD / 255.0, blue: 0xFF / 255.0)
    public static let lightBackground = Color(red: 0xFD / 255.0, green: 0xF8 / 255.0, blue: 0xFF / 255.0)
    public static let lightSurfaceContainer = Color(red: 0xF2 / 255.0, green: 0xEC / 255.0, blue: 0xF4 / 255.0)

    // Dark
    public static let darkPrimary = Color(red: 0x9F / 255.0, green: 0x82 / 255.0, blue: 0xDC / 255.0)
    public static let darkPrimaryContainer = Color(red: 0x4A / 255.0, green: 0x2F / 255.0, blue: 0x7C / 255.0)
    public static let darkBackground = Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x18 / 255.0)
    public static let darkSurfaceContainer = Color(red: 0x21 / 255.0, green: 0x1F / 255.0, blue: 0x24 / 255.0)

    public static func primary(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkPrimary : lightPrimary
    }

    public static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkBackground : lightBackground
    }

    public static func cardBackground(for scheme: ColorScheme) -> Color {
        scheme == .dark ? darkSurfaceContainer : lightSurfaceContainer
    }
}

public struct LilacRemoteImage: View {
    public let url: String
    public var contentMode: ContentMode = .fill

    public init(url: String, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    public var body: some View {
        if let parsed = URL(string: url), !url.isEmpty {
            AsyncImage(url: parsed) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        Color.purple.opacity(0.12)
                        ProgressView()
                    }
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.purple.opacity(0.25), Color.indigo.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "sparkles.tv")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}

public struct ScreenHeader<Actions: View>: View {
    public let title: String
    public let subtitle: String?
    public let actions: Actions

    public init(title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    public var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.title2.bold())
            }
            Spacer()
            actions
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

public struct HeroCardView: View {
    public let anime: Anime
    public let onOpen: (Anime) -> Void

    public var body: some View {
        Button {
            onOpen(anime)
        } label: {
            ZStack(alignment: .bottomLeading) {
                LilacRemoteImage(url: anime.backdrop.isEmpty ? anime.poster : anime.backdrop)
                    .frame(height: 250)
                    .clipped()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 6) {
                    if !anime.note.isEmpty {
                        Text(anime.note)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    Text(anime.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if !anime.genres.isEmpty {
                        Text(anime.genres.prefix(3).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(16)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 20)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

public struct AnimeCardView: View {
    public let anime: Anime
    public var width: CGFloat = 136
    public let onOpen: (Anime) -> Void

    public var body: some View {
        Button {
            onOpen(anime)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    LilacRemoteImage(url: anime.poster)
                        .frame(width: width, height: width * 1.42)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    if !anime.note.isEmpty {
                        Text(anime.note)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(6)
                    }
                }

                Text(anime.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(width: width, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

public struct AnimeRailView: View {
    public let title: String
    public let items: [Anime]
    public let onOpen: (Anime) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { anime in
                        AnimeCardView(anime: anime, onOpen: onOpen)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 6)
    }
}
