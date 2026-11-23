import Foundation

/// iOS port of `SubtitleCue`, `SubtitleFormatTranslator` parser/renderer, `JimakuSubtitleService`, `AnissiaSubtitleService`, `KairanSubtitleService`, `CsoraSubtitleService`, and `SubtitleStore`.
public struct SubtitleCue: Identifiable, Codable, Hashable, Sendable {
    public var id: Int { index }
    public var index: Int
    public var startMs: Int64
    public var endMs: Int64
    public var text: String
    public var rawLine: String
    public var kind: String // ass, srt, vtt, smi
    public var styleName: String?
    public var translatedText: String?

    public var displayText: String {
        if let translatedText, !translatedText.isEmpty {
            return translatedText
        }
        return Self.cleanDisplay(text)
    }

    public init(
        index: Int,
        startMs: Int64,
        endMs: Int64,
        text: String,
        rawLine: String = "",
        kind: String = "srt",
        styleName: String? = nil,
        translatedText: String? = nil
    ) {
        self.index = index
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.rawLine = rawLine
        self.kind = kind
        self.styleName = styleName
        self.translatedText = translatedText
    }

    public static func cleanDisplay(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum SubtitleParser {
    public static func readSubtitleText(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        return decodeSubtitleBytes(data)
    }

    public static func decodeSubtitleBytes(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8.replacingOccurrences(of: "\u{FEFF}", with: "")
        }
        let eucKr = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))
        if let str = String(data: data, encoding: eucKr) {
            return str
        }
        if let sjis = String(data: data, encoding: .shiftJIS) {
            return sjis
        }
        if let utf16 = String(data: data, encoding: .utf16) {
            return utf16
        }
        return String(decoding: data, as: UTF8.self)
    }

    public static func parse(content: String, ext: String = "") -> [SubtitleCue] {
        let lowerExt = ext.lowercased()
        switch lowerExt {
        case "ass", "ssa": return parseAss(content)
        case "srt": return parseSrt(content)
        case "vtt": return parseVtt(content)
        case "smi", "sami": return parseSmi(content)
        default:
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.uppercased().hasPrefix("WEBVTT") { return parseVtt(content) }
            if content.range(of: "(?im)^Dialogue:", options: .regularExpression) != nil { return parseAss(content) }
            if content.range(of: "(?is)<SAMI|<SYNC\\s+Start\\s*=", options: .regularExpression) != nil { return parseSmi(content) }
            return parseSrt(content)
        }
    }

    public static func parseAss(_ content: String) -> [SubtitleCue] {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var cues: [SubtitleCue] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("dialogue:") else { continue }
            let body = trimmed.dropFirst("dialogue:".count).trimmingCharacters(in: .whitespaces)
            let parts = Self.splitAssDialogue(String(body), limit: 10)
            guard parts.count >= 10 else { continue }
            let startMs = parseAssTime(parts[1])
            let endMs = parseAssTime(parts[2])
            let style = parts[3]
            let rawText = parts[9]
            let clean = SubtitleCue.cleanDisplay(rawText)
            guard !clean.isEmpty, endMs > startMs else { continue }
            cues.append(SubtitleCue(
                index: cues.count,
                startMs: startMs,
                endMs: endMs,
                text: rawText,
                rawLine: line,
                kind: "ass",
                styleName: style
            ))
        }
        return cues
    }

    public static func parseSrt(_ content: String) -> [SubtitleCue] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [SubtitleCue] = []

        for block in blocks {
            let lines = block.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            guard let arrowIdx = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let timeLine = lines[arrowIdx]
            let timeParts = timeLine.components(separatedBy: "-->")
            guard timeParts.count >= 2 else { continue }
            let startMs = parseSrtVttTime(timeParts[0])
            let endMs = parseSrtVttTime(timeParts[1].components(separatedBy: " ").first ?? timeParts[1])
            let textLines = lines.dropFirst(arrowIdx + 1)
            let text = textLines.joined(separator: "\n")
            guard !text.isEmpty, endMs > startMs else { continue }
            cues.append(SubtitleCue(
                index: cues.count,
                startMs: startMs,
                endMs: endMs,
                text: text,
                rawLine: block,
                kind: "srt"
            ))
        }
        return cues
    }

    public static func parseVtt(_ content: String) -> [SubtitleCue] {
        var cues = parseSrt(content)
        for i in cues.indices {
            cues[i].kind = "vtt"
        }
        return cues
    }

    public static func parseSmi(_ content: String) -> [SubtitleCue] {
        let matches = HTMLParser.allMatches("<SYNC\\s+Start\\s*=\\s*(\\d+)[^>]*>(.*?)(?=<SYNC\\s+Start|</BODY|</SAMI|$)", in: content)
        var rawPairs: [(Int64, String)] = []
        for match in matches where match.count >= 3 {
            guard let ms = Int64(match[1]) else { continue }
            let body = match[2].replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
            let clean = HTMLParser.stripTags(body)
            rawPairs.append((ms, clean))
        }
        var cues: [SubtitleCue] = []
        for i in 0..<rawPairs.count {
            let (start, text) = rawPairs[i]
            guard !text.isEmpty else { continue }
            let end = (i + 1 < rawPairs.count) ? rawPairs[i + 1].0 : (start + 3500)
            guard end > start else { continue }
            cues.append(SubtitleCue(
                index: cues.count,
                startMs: start,
                endMs: min(end, start + 12_000),
                text: text,
                kind: "smi"
            ))
        }
        return cues
    }

    public static func renderTranslatedFile(originalContent: String, ext: String, cues: [SubtitleCue]) -> String {
        let lowerExt = ext.lowercased()
        if lowerExt == "ass" || lowerExt == "ssa" || originalContent.range(of: "(?im)^Dialogue:", options: .regularExpression) != nil {
            var lines = originalContent.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            var cueIdx = 0
            for i in lines.indices {
                let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                if trimmed.lowercased().hasPrefix("dialogue:"), cueIdx < cues.count {
                    let cue = cues[cueIdx]
                    cueIdx += 1
                    if let translated = cue.translatedText, !translated.isEmpty {
                        let body = String(trimmed.dropFirst("dialogue:".count)).trimmingCharacters(in: .whitespaces)
                        var parts = splitAssDialogue(body, limit: 10)
                        if parts.count >= 10 {
                            let leadingTags = HTMLParser.allMatches("^(\\{[^}]*\\})+", in: parts[9]).first?.first ?? ""
                            parts[9] = leadingTags + translated.replacingOccurrences(of: "\n", with: "\\N")
                            lines[i] = "Dialogue: " + parts.joined(separator: ",")
                        }
                    }
                }
            }
            return lines.joined(separator: "\n")
        } else {
            // Render standard SRT/VTT
            let isVtt = lowerExt == "vtt" || originalContent.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("WEBVTT")
            var out: [String] = isVtt ? ["WEBVTT", ""] : []
            for (idx, cue) in cues.enumerated() {
                if !isVtt {
                    out.append(String(idx + 1))
                }
                let sep = isVtt ? "." : ","
                out.append("\(formatTime(cue.startMs, sep: sep)) --> \(formatTime(cue.endMs, sep: sep))")
                out.append(cue.translatedText ?? cue.text)
                out.append("")
            }
            return out.joined(separator: "\n")
        }
    }

    private static func splitAssDialogue(_ line: String, limit: Int) -> [String] {
        var parts: [String] = []
        var current = ""
        for ch in line {
            if ch == "," && parts.count < limit - 1 {
                parts.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        parts.append(current)
        return parts
    }

    private static func parseAssTime(_ raw: String) -> Int64 {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let hmsc = trimmed.components(separatedBy: ":")
        guard hmsc.count == 3 else { return 0 }
        let h = Int64(hmsc[0]) ?? 0
        let m = Int64(hmsc[1]) ?? 0
        let secParts = hmsc[2].components(separatedBy: ".")
        let s = Int64(secParts[0]) ?? 0
        let cs = secParts.count > 1 ? (Int64(secParts[1].padding(toLength: 2, withPad: "0", startingAt: 0).prefix(2)) ?? 0) : 0
        return ((h * 3600 + m * 60 + s) * 1000) + (cs * 10)
    }

    private static func parseSrtVttTime(_ raw: String) -> Int64 {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = trimmed.components(separatedBy: ":")
        let h: Int64
        let m: Int64
        let sPart: String
        if parts.count == 3 {
            h = Int64(parts[0]) ?? 0
            m = Int64(parts[1]) ?? 0
            sPart = parts[2]
        } else if parts.count == 2 {
            h = 0
            m = Int64(parts[0]) ?? 0
            sPart = parts[1]
        } else {
            return 0
        }
        let secSub = sPart.components(separatedBy: ".")
        let s = Int64(secSub[0]) ?? 0
        let ms = secSub.count > 1 ? (Int64(secSub[1].padding(toLength: 3, withPad: "0", startingAt: 0).prefix(3)) ?? 0) : 0
        return ((h * 3600 + m * 60 + s) * 1000) + ms
    }

    public static func formatTime(_ ms: Int64, sep: String = ",") -> String {
        let totalSec = max(0, ms) / 1000
        let millis = max(0, ms) % 1000
        let h = totalSec / 3600
        let m = (totalSec % 3600) / 60
        let s = totalSec % 60
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, sep, millis)
    }
}

/// iOS port of `SubtitleStore`, `JimakuSubtitleService`, and `AnissiaSubtitleService`.
public final class SubtitleDiscoveryService: @unchecked Sendable {
    public static let shared = SubtitleDiscoveryService()

    public struct SubtitleOption: Identifiable, Codable, Hashable, Sendable {
        public var id: String { "\(source)::\(name)::\(url)" }
        public var source: String // linkkf, reanime, jimaku, anissia, kairan, csora, local
        public var name: String
        public var creator: String
        public var updateDate: String
        public var url: String
        public var format: String
        public var cachedPath: String?
        public var isBundle: Bool

        public init(
            source: String,
            name: String,
            creator: String = "",
            updateDate: String = "",
            url: String = "",
            format: String = "srt",
            cachedPath: String? = nil,
            isBundle: Bool = false
        ) {
            self.source = source
            self.name = name
            self.creator = creator
            self.updateDate = updateDate
            self.url = url
            self.format = format
            self.cachedPath = cachedPath
            self.isBundle = isBundle
        }
    }

    private let http = HttpClient.shared
    private let fileManager = FileManager.default
    private var jimakuEntryCache: [Int: String] = [:]

    private init() {
        try? fileManager.createDirectory(at: subtitleDirectory, withIntermediateDirectories: true)
    }

    public var subtitleDirectory: URL {
        OfflineStore.shared.rootDirectory.appendingPathComponent("subtitles", isDirectory: true)
    }

    // MARK: - Jimaku (Japanese Subtitles via AniList ID)

    public func listJimakuSubtitles(anime: Anime, episodeNumber: Int) async -> [SubtitleOption] {
        guard let anilistId = anime.anilistId, anilistId > 0, episodeNumber > 0 else { return [] }
        guard let entryId = await resolveJimakuEntryId(anilistId: anilistId) else { return [] }
        let url = "https://jimaku.cc/entry/\(entryId)"
        guard let html = try? await http.getText(url: url, referer: "https://jimaku.cc/") else { return [] }

        let extras = HTMLParser.allMatches("<div[^>]*class\\s*=\\s*[\"'][^\"']*entry[^\"']*[\"'][^>]*data-extra\\s*=\\s*[\"']([^\"']+)[\"']", in: html)
        let supportedExts: Set<String> = ["ass", "ssa", "srt", "vtt", "zip"]
        var options: [SubtitleOption] = []

        for match in extras where match.count > 1 {
            let decodedJson = HTMLParser.decodeEntities(match[1])
            guard let data = decodedJson.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
            let name = (obj["name"] as? String) ?? ""
            let href = (obj["url"] as? String) ?? ""
            let ext = (name.components(separatedBy: ".").last ?? "").lowercased()
            guard !name.isEmpty, !href.isEmpty, supportedExts.contains(ext) else { continue }

            if Self.matchesEpisode(filename: name, episodeNumber: episodeNumber) || ext == "zip" {
                let fullUrl = HTMLParser.resolveURL(href, base: "https://jimaku.cc")
                options.append(SubtitleOption(
                    source: "jimaku",
                    name: name,
                    creator: "Jimaku (일본어)",
                    url: fullUrl,
                    format: ext,
                    isBundle: ext == "zip"
                ))
            }
        }
        return options
    }

    private func resolveJimakuEntryId(anilistId: Int) async -> String? {
        if let cached = jimakuEntryCache[anilistId] { return cached }
        guard let html = try? await http.getText(url: "https://jimaku.cc/", referer: "https://jimaku.cc/") else { return nil }
        let blocks = HTMLParser.allMatches("<div[^>]*class\\s*=\\s*[\"'][^\"']*entry[^\"']*[\"'][^>]*data-extra\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</div>", in: html)
        for block in blocks where block.count >= 3 {
            let jsonText = HTMLParser.decodeEntities(block[1])
            guard let data = jsonText.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  (obj["anilist_id"] as? Int) == anilistId else { continue }
            if let entryId = HTMLParser.firstMatch("/entry/(\\d+)", in: block[2]) {
                jimakuEntryCache[anilistId] = entryId
                return entryId
            }
        }
        return nil
    }

    // MARK: - Anissia (Korean Fan Subtitles & Creator Blog Resolver)

    public func listAnissiaSubtitles(animeTitle: String, episodeNumber: Int) async -> [SubtitleOption] {
        let query = animeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let enc = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        let listUrl = "https://api.anissia.net/anime/list/0/\(enc)"

        guard let raw = try? await http.getText(
            url: listUrl,
            headers: ["Accept": "application/json"],
            referer: "https://anissia.net/",
            userAgent: HttpClient.desktopUserAgent
        ),
        let data = raw.data(using: .utf8),
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let content = (root["data"] as? [String: Any])?["content"] as? [[String: Any]],
        let firstAnime = content.first,
        let animeNo = firstAnime["animeNo"] as? Int else {
            return []
        }

        let captionUrl = "https://api.anissia.net/anime/caption/animeNo/\(animeNo)"
        guard let capRaw = try? await http.getText(
            url: captionUrl,
            headers: ["Accept": "application/json"],
            referer: "https://anissia.net/",
            userAgent: HttpClient.desktopUserAgent
        ),
        let capData = capRaw.data(using: .utf8),
        let capRoot = (try? JSONSerialization.jsonObject(with: capData)) as? [String: Any],
        let captions = capRoot["data"] as? [[String: Any]] else {
            return []
        }

        return captions.compactMap { item in
            let creator = (item["name"] as? String) ?? "Anissia 제작자"
            let website = (item["website"] as? String) ?? ""
            let episode = (item["episode"] as? String) ?? String(episodeNumber)
            let updDt = String(((item["updDt"] as? String) ?? "").prefix(10))
            guard website.hasPrefix("http") else { return nil }
            return SubtitleOption(
                source: "anissia",
                name: "\(creator) · \(episode)화 (\(updDt))",
                creator: creator,
                updateDate: updDt,
                url: website,
                format: "smi"
            )
        }
    }

    // MARK: - Download & Cache Subtitle File

    public func downloadSubtitle(option: SubtitleOption, animeId: String, episodeKey: String, referer: String? = nil) async -> URL? {
        if let cached = option.cachedPath, fileManager.fileExists(atPath: cached) {
            return URL(fileURLWithPath: cached)
        }
        guard !option.url.isEmpty else { return nil }

        do {
            // If it's an Anissia creator blog page, scan the page for direct subtitle attachment links (.smi/.srt/.ass)
            var targetDownloadUrl = option.url
            if option.source == "anissia" && !Self.isDirectSubtitleUrl(option.url) {
                if let extracted = try? await extractSubtitleAttachmentFromBlog(blogUrl: option.url) {
                    targetDownloadUrl = extracted
                }
            }

            let (data, resp) = try await http.getData(
                url: targetDownloadUrl,
                referer: referer ?? option.url,
                userAgent: HttpClient.desktopUserAgent
            )
            guard (200...299).contains(resp.statusCode), !data.isEmpty else { return nil }

            let detectedExt = Self.detectExtension(from: data, fallbackUrl: targetDownloadUrl, defaultExt: option.format)
            let safeKey = OfflineStore.safeFilename("\(animeId)_\(episodeKey)_\(option.source)")
            let outURL = subtitleDirectory.appendingPathComponent("\(safeKey).\(detectedExt)")
            try data.write(to: outURL, options: .atomic)
            return outURL
        } catch {
            return nil
        }
    }

    private func extractSubtitleAttachmentFromBlog(blogUrl: String) async throws -> String? {
        let html = try await http.getText(url: blogUrl, referer: "https://anissia.net/", userAgent: HttpClient.desktopUserAgent)
        let normalized = HTMLParser.decodeEntities(html).replacingOccurrences(of: "\\/", with: "/")
        let patterns = [
            "(?:encodedAttachFileUrl|attachFileUrl)[\"']?\\s*[:=]\\s*[\"']([^\"']+)[\"']",
            "https?://blogattach\\.naver\\.com/[^\\s\"'<>\\\\]+",
            "https?://[^\\s\"'<>\\\\]+/attachment/[^\\s\"'<>\\\\]+",
            "https?://[^\\s\"'<>\\\\]+?\\.(?:ass|ssa|srt|smi|sami|vtt)(?:\\?[^\\s\"'<>\\\\]*)?"
        ]
        for pattern in patterns {
            if let match = HTMLParser.firstMatch(pattern, in: normalized, group: 1) ?? HTMLParser.firstMatch("(\(pattern))", in: normalized, group: 1) {
                return match
            }
        }
        return nil
    }

    private static func isDirectSubtitleUrl(_ url: String) -> Bool {
        let lower = url.components(separatedBy: "?").first?.lowercased() ?? ""
        return ["ass", "ssa", "srt", "smi", "sami", "vtt"].contains { lower.hasSuffix(".\($0)") }
    }

    private static func detectExtension(from data: Data, fallbackUrl: String, defaultExt: String) -> String {
        let text = (SubtitleParser.decodeSubtitleBytes(data) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.uppercased().hasPrefix("WEBVTT") { return "vtt" }
        if text.range(of: "(?im)^Dialogue:", options: .regularExpression) != nil { return "ass" }
        if text.range(of: "(?is)<SAMI|<SYNC\\s+Start", options: .regularExpression) != nil { return "smi" }
        if text.contains("-->") { return "srt" }
        let urlExt = URL(string: fallbackUrl)?.pathExtension.lowercased() ?? ""
        if ["ass", "ssa", "srt", "smi", "vtt"].contains(urlExt) { return urlExt }
        return defaultExt.isEmpty ? "srt" : defaultExt
    }

    public static func matchesEpisode(filename: String, episodeNumber: Int) -> Bool {
        let patterns = [
            "(?i)(?:^|[^0-9])0*\(episodeNumber)(?:화|회|ep|v\\d|\\b)",
            "(?i)[\\s._\\-\\[(]0*\(episodeNumber)[\\s._\\-\\])]"
        ]
        for p in patterns {
            if filename.range(of: p, options: .regularExpression) != nil {
                return true
            }
        }
        return false
    }
}
