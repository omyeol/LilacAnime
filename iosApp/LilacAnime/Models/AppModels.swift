import Foundation
import CoreGraphics

public struct StreamQuality: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(label)::\(url)" }
    public var label: String
    public var url: String
    public var referer: String? = nil
    public var headers: String? = nil
    public var flixCloudPk: String? = nil

    public init(
        label: String,
        url: String,
        referer: String? = nil,
        headers: String? = nil,
        flixCloudPk: String? = nil
    ) {
        self.label = label
        self.url = url
        self.referer = referer
        self.headers = headers
        self.flixCloudPk = flixCloudPk
    }
}

public struct PlayerSettings: Codable, Hashable, Sendable {
    public var defaultQuality: String = "1080p"
    public var videoSourcePreference: String = "linkkf" // linkkf, reanime, miruro, ohli24, animenosub
    public var subtitleFont: String = "기본체"
    public var subtitleSize: Float = 100.0
    public var textColorHex: UInt32 = 0xFFFFFFFF
    public var backgroundColorHex: UInt32 = 0x00000000
    public var strokeColorHex: UInt32 = 0xFF000000
    public var syncOffsetMs: Int64 = 0
    public var subtitleBottomPaddingFraction: Float = 0.12
    public var subtitleSourcePreference: String = "linkkf" // linkkf, reanime, jimaku, anissia, local
    public var customFontPath: String? = nil
    public var subtitleFontPath: String? = nil
    public var subtitleFontSource: String? = nil
    public var showChapterSkipButton: Bool = true
    public var offlineOpEdAnalysisEnabled: Bool = true
    public var doubleTapSeekSeconds: Int64 = 10
    public var seekButtonSeekSeconds: Int64 = 10
    public var playbackSpeed: Float = 1.0
    public var autoPlay: Bool = true
    public var autoSkip: Bool = true
    public var vttStyleEnabled: Bool = true
    public var vttBold: Bool = true
    public var vttOutlineWidth: Float = 2.0
    public var assEffectsEnabled: Bool = true
    public var translationAutoEnabled: Bool = false
    public var translationProvider: String = "local" // local, gemini, openai, deepl, qwen
    public var translationModelId: String? = nil
    public var translationSystemPrompt: String = CloudTranslationPrompt.defaultSystemPrompt
    public var translationPrompt: String = LocalAiTranslationRuntime.defaultPrompt
    public var aiContextSize: Int = 4096
    public var aiThreads: Int = 0
    public var aiMaxTokens: Int = 512
    public var aiTemperature: Float = 0.25
    public var aiTopP: Float = 0.85
    public var aiTopK: Int = 40
    public var aiRepetitionPenalty: Float = 1.05
    public var aiThinkingMode: String = "off" // off, on, auto
    public var aiContextCues: Int = 6
    public var aiPrefetchEnabled: Bool = true
    public var aiPrefetchAhead: Int = 10
    public var aiBatchSize: Int = 5
    public var playbackAiMode: String = "default" // default, anime4k, whisper
    public var aiUpscalingEnabled: Bool = false
    public var aiUpscalingBackend: String = "metal" // metal, anime4k
    public var aiUpscalingMode: String = "A" // A, B, C, A+A, B+B, C+A
    public var aiUpscalingScale: Int = 2
    public var watermarkRemovalEnabled: Bool = false
    public var watermarkRegions: String = "" // normalized "x,y,w,h" joined by ';'
    public var subtitleEraseEnabled: Bool = false
    public var subtitleEraseRegions: String = "" // normalized "x,y,w,h" joined by ';'
    public var subtitleEraseStrictOutline: Bool = false
    public var subtitleEraseLimitLength: Bool = false
    public var subtitleEraseDebugMask: Bool = false
    public var ambientModeEnabled: Bool = false
    public var ambientCropBlackBars: Bool = true
    public var subtitleOverrideEnabled: Bool = false
    public var qwenRegion: String = "international" // international, china
    public var geminiModel: String = "gemini-2.5-flash"
    public var openAIModel: String = "gpt-4.1-mini"
    public var qwenModel: String = "qwen-plus"
    public var tmdbApiKey: String = ""

    public init() {}
}

public struct ChapterSkipSegment: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(type):\(startTime)-\(endTime)" }
    public var type: String // op, ed, mixed-op, mixed-ed, recap
    public var startTime: Double
    public var endTime: Double
    public var episodeLength: Double

    public var displayLabel: String {
        switch type.lowercased() {
        case "op", "mixed-op": return "오프닝 건너뛰기"
        case "ed", "mixed-ed": return "엔딩 건너뛰기"
        case "recap": return "줄거리 요약 건너뛰기"
        default: return "구간 건너뛰기"
        }
    }

    public init(type: String, startTime: Double, endTime: Double, episodeLength: Double = 0) {
        self.type = type
        self.startTime = startTime
        self.endTime = endTime
        self.episodeLength = episodeLength
    }
}

public struct NormalizedRegionRect: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(x),\(y),\(width),\(height)" }
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = max(0, min(1, x))
        self.y = max(0, min(1, y))
        self.width = max(0.01, min(1 - self.x, width))
        self.height = max(0.01, min(1 - self.y, height))
    }

    public static func parseList(_ raw: String) -> [NormalizedRegionRect] {
        raw.split(separator: ";").compactMap { part in
            let nums = part.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
            guard nums.count == 4 else { return nil }
            return NormalizedRegionRect(x: nums[0], y: nums[1], width: nums[2], height: nums[3])
        }
    }

    public static func serializeList(_ rects: [NormalizedRegionRect]) -> String {
        rects.map { String(format: "%.4f,%.4f,%.4f,%.4f", $0.x, $0.y, $0.width, $0.height) }
            .joined(separator: ";")
    }
}

public enum ThemeMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case system = "SYSTEM"
    case light = "LIGHT"
    case dark = "DARK"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "시스템 설정 따르기"
        case .light: return "라이트 모드"
        case .dark: return "다크 모드"
        }
    }
}
