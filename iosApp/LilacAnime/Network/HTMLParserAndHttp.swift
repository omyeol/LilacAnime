import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif

/// HTML extraction and CSS-like query helpers replacing Jsoup in pure Swift.
public enum HTMLParser {
    public static func decodeEntities(_ text: String) -> String {
        var result = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#8211;", with: "–")
            .replacingOccurrences(of: "&#8212;", with: "—")
            .replacingOccurrences(of: "&#8217;", with: "’")
            .replacingOccurrences(of: "&#8220;", with: "“")
            .replacingOccurrences(of: "&#8221;", with: "”")

        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9A-Fa-f]+);") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
            for match in matches {
                guard let codeRange = Range(match.range(at: 1), in: result),
                      let fullRange = Range(match.range, in: result) else { continue }
                let raw = String(result[codeRange])
                let code: UInt32? = raw.lowercased().hasPrefix("x")
                    ? UInt32(raw.dropFirst(), radix: 16)
                    : UInt32(raw, radix: 10)
                if let c = code, let scalar = UnicodeScalar(c) {
                    result.replaceSubrange(fullRange, with: String(scalar))
                }
            }
        }
        return result
    }

    public static func stripTags(_ html: String) -> String {
        let withoutScripts = html.replacingOccurrences(
            of: "(?is)<(script|style)[^>]*>.*?</\\1>",
            with: "",
            options: .regularExpression
        )
        let stripped = withoutScripts.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        return decodeEntities(stripped)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func firstMatch(_ pattern: String, in text: String, group: Int = 1, options: NSRegularExpression.Options = [.dotMatchesLineSeparators, .caseInsensitive]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        guard match.numberOfRanges > group, let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }

    public static func allMatches(_ pattern: String, in text: String, options: NSRegularExpression.Options = [.dotMatchesLineSeparators, .caseInsensitive]) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return matches.map { match in
            (0..<match.numberOfRanges).map { idx in
                guard let range = Range(match.range(at: idx), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    public static func attribute(_ name: String, in tagHTML: String) -> String? {
        let pattern = "(?i)\\b\(NSRegularExpression.escapedPattern(for: name))\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        guard let match = regex.firstMatch(in: tagHTML, range: NSRange(tagHTML.startIndex..., in: tagHTML)) else { return nil }
        for group in 1...3 {
            if match.numberOfRanges > group,
               let range = Range(match.range(at: group), in: tagHTML) {
                return decodeEntities(String(tagHTML[range]))
            }
        }
        return nil
    }

    public static func resolveURL(_ href: String, base: String) -> String {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }
        if let baseURL = URL(string: base), let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
            return resolved.absoluteString
        }
        let cleanBase = base.hasSuffix("/") ? String(base.dropLast()) : base
        return trimmed.hasPrefix("/") ? "\(cleanBase)\(trimmed)" : "\(cleanBase)/\(trimmed)"
    }
}

public enum NetworkError: LocalizedError {
    case invalidURL(String)
    case httpError(Int, String)
    case emptyResponse(String)
    case parseError(String)
    case cloudflareChallenge(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "잘못된 URL입니다: \(url)"
        case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(240))"
        case .emptyResponse(let url): return "응답이 비어 있습니다: \(url)"
        case .parseError(let reason): return "데이터 파싱 오류: \(reason)"
        case .cloudflareChallenge(let url): return "Cloudflare 보안 인증이 필요합니다: \(url)"
        }
    }
}

/// Shared Cloudflare session and HTTP client mirroring Android's `CloudflareSession` and `OkHttpClient`.
public final class HttpClient: @unchecked Sendable {
    public static let shared = HttpClient()

    public static let mobileUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
    public static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        self.session = URLSession(configuration: config)
    }

    public func getData(
        url: String,
        headers: [String: String] = [:],
        referer: String? = nil,
        userAgent: String = HttpClient.mobileUserAgent
    ) async throws -> (Data, HTTPURLResponse) {
        guard let targetURL = URL(string: url) else {
            throw NetworkError.invalidURL(url)
        }
        var request = URLRequest(url: targetURL)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7", forHTTPHeaderField: "Accept-Language")
        if let referer = referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.emptyResponse(url)
        }
        if isCloudflareChallenge(http: http, body: data) {
            throw NetworkError.cloudflareChallenge(url)
        }
        return (data, http)
    }

    public func getText(
        url: String,
        headers: [String: String] = [:],
        referer: String? = nil,
        userAgent: String = HttpClient.mobileUserAgent
    ) async throws -> String {
        let (data, http) = try await getData(url: url, headers: headers, referer: referer, userAgent: userAgent)
        guard (200...299).contains(http.statusCode) else {
            let preview = String(data: data, encoding: .utf8) ?? ""
            throw NetworkError.httpError(http.statusCode, preview)
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        // Fallback for EUC-KR / CP949 pages (Korean subtitle blogs)
        let eucKrEncoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)))
        if let eucKr = String(data: data, encoding: eucKrEncoding) {
            return eucKr
        }
        return String(decoding: data, as: UTF8.self)
    }

    public func postData(
        url: String,
        body: Data,
        contentType: String = "application/json; charset=utf-8",
        headers: [String: String] = [:],
        referer: String? = nil,
        userAgent: String = HttpClient.mobileUserAgent
    ) async throws -> (Data, HTTPURLResponse) {
        guard let targetURL = URL(string: url) else {
            throw NetworkError.invalidURL(url)
        }
        var request = URLRequest(url: targetURL)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let referer = referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NetworkError.emptyResponse(url)
        }
        return (data, http)
    }

    public func isCloudflareChallenge(http: HTTPURLResponse, body: Data) -> Bool {
        if http.value(forHTTPHeaderField: "cf-mitigated")?.lowercased() == "challenge" {
            return true
        }
        guard http.statusCode == 403 || http.statusCode == 503 else { return false }
        let text = String(data: body.prefix(4096), encoding: .utf8)?.lowercased() ?? ""
        return text.contains("__cf_chl_") || text.contains("cf-turnstile") || text.contains("just a moment...")
    }
}
