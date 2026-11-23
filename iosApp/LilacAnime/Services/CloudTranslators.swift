import Foundation
import Security

/// iOS Keychain store replacing Android's `SecureApiKeyStore` (`EncryptedSharedPreferences`).
public enum SecureApiKeyStore {
    private static let serviceName = "com.lilac.anime.ios.apikeys"

    public static func set(providerId: String, apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = providerId.lowercased()
        delete(providerId: account)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    public static func get(providerId: String) -> String? {
        let account = providerId.lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func has(providerId: String) -> Bool {
        guard let key = get(providerId: providerId) else { return false }
        return !key.isEmpty
    }

    public static func delete(providerId: String) {
        let account = providerId.lowercased()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// iOS port of `CloudTranslationPrompt` and `CloudTranslationText`.
public enum CloudTranslationPrompt {
    public static let defaultSystemPrompt = """
    You are an experienced Korean anime subtitle translator working to the standard of a good Korean fansub team.
    Translate Japanese or English anime subtitles into natural spoken Korean.
    Read the lines as a scene and keep speaker relationships and character voice consistent.
    Preserve meaning faithfully. Do not add explanations, censor, invent, merge, split, skip, or reorder lines.
    Keep each subtitle concise and natural. Avoid translationese such as unnecessary 그녀/그/당신 or literal idioms.
    Friends, family and classmates normally use 반말; strangers and superiors normally use 존댓말. Keep each character's speech style consistent.
    Use established Korean anime spellings for names. Translate common honorifics naturally: 先輩→선배, 先生→선생님, お兄ちゃん/兄さん according to the speaker.
    Keep stammers, interruptions, sound effects, music marks and bracketed caption labels where appropriate.
    Return exactly one translated item for every input item, with the same numeric index.
    Output only the requested JSON structure and nothing else.
    """

    public static let defaultUserInstruction = "주어진 자막을 자연스러운 한국어로 번역해. 입력한 순서와 줄 수를 그대로 유지해."

    public static func userMessage(settings: PlayerSettings, lines: [String]) -> String {
        let user = settings.translationPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? defaultUserInstruction
            : settings.translationPrompt
        let marked = markedInput(lines)
        let replaced = user
            .replacingOccurrences(of: "{context}", with: "")
            .replacingOccurrences(of: "{future_context}", with: "")
            .replacingOccurrences(of: "{source_text}", with: marked)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return replaced.contains("<LILAC_") ? replaced : "\(replaced)\n\n\(marked)"
    }

    public static func markedInput(_ lines: [String]) -> String {
        lines.enumerated().map { idx, line in
            "<LILAC_\(idx + 1)> \(line)"
        }.joined(separator: "\n")
    }

    public static func objectSchema() -> [String: Any] {
        let item: [String: Any] = [
            "type": "object",
            "properties": [
                "i": ["type": "integer"],
                "t": ["type": "string"]
            ],
            "required": ["i", "t"],
            "additionalProperties": false
        ]
        return [
            "type": "object",
            "properties": [
                "lines": [
                    "type": "array",
                    "items": item
                ]
            ],
            "required": ["lines"],
            "additionalProperties": false
        ]
    }
}

public enum CloudTranslationText {
    public static func parseMarked(_ text: String, original: [String]) throws -> [String] {
        if original.isEmpty { return [] }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        if let jsonLines = parseJsonLines(normalized, original: original) {
            return jsonLines
        }

        guard let regex = try? NSRegularExpression(pattern: "<LILAC_(\\d+)>") else {
            throw NetworkError.parseError("정규식 초기화 실패")
        }
        let matches = regex.matches(in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
        if matches.isEmpty {
            if original.count == 1 && !normalized.isEmpty {
                return [stripFences(normalized)]
            }
            throw NetworkError.parseError("API 응답에서 자막 구분 표식(<LILAC_N>)을 찾지 못했습니다.")
        }

        var result = Array(repeating: "", count: original.count)
        for (mIdx, match) in matches.enumerated() {
            guard let numRange = Range(match.range(at: 1), in: normalized),
                  let lineIndex = Int(normalized[numRange]).map({ $0 - 1 }),
                  result.indices.contains(lineIndex),
                  let matchRange = Range(match.range, in: normalized) else { continue }
            let start = matchRange.upperBound
            let end: String.Index
            if mIdx + 1 < matches.count, let nextRange = Range(matches[mIdx + 1].range, in: normalized) {
                end = nextRange.lowerBound
            } else {
                end = normalized.endIndex
            }
            var segment = String(normalized[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if segment.hasPrefix(":") {
                segment = String(segment.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            result[lineIndex] = stripFences(segment)
        }
        if result.contains(where: { $0.isEmpty }) {
            throw NetworkError.parseError("API 응답에서 일부 자막 번역이 누락되었습니다.")
        }
        return result
    }

    private static func parseJsonLines(_ text: String, original: [String]) -> [String]? {
        let clean = stripFences(text)
        guard let data = clean.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        let values: [[String: Any]]
        if let dict = json as? [String: Any], let arr = dict["lines"] as? [[String: Any]] {
            values = arr
        } else if let arr = json as? [[String: Any]] {
            values = arr
        } else {
            return nil
        }
        var result = Array(repeating: "", count: original.count)
        for (i, item) in values.enumerated() {
            let idx = ((item["i"] as? Int) ?? (i + 1)) - 1
            let t = ((item["t"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if result.indices.contains(idx) && !t.isEmpty {
                result[idx] = t
            }
        }
        return result.allSatisfy({ !$0.isEmpty }) ? result : nil
    }

    public static func stripFences(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["```json", "```text", "```txt", "```"] {
            if s.hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                break
            }
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3))
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public protocol TranslationProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func translateBatch(_ lines: [String], settings: PlayerSettings) async throws -> [String]
    func testConnection(settings: PlayerSettings) async throws -> String
}

/// iOS port of `GeminiTranslator`.
public final class GeminiTranslator: TranslationProvider {
    public let id = "gemini"
    public let displayName = "Gemini"
    private let http = HttpClient.shared

    public init() {}

    public func testConnection(settings: PlayerSettings) async throws -> String {
        guard let key = SecureApiKeyStore.get(providerId: id), !key.isEmpty else {
            throw NetworkError.parseError("Gemini API Key가 없습니다. AI 설정에서 키를 저장하세요.")
        }
        let models = try await listModels(key: key)
        guard let first = models.first else {
            throw NetworkError.parseError("이 Gemini API 키로 사용할 수 있는 generateContent 모델이 없습니다.")
        }
        return "연결 성공: \(first) (사용 가능 모델 \(models.count)개)"
    }

    public func translateBatch(_ lines: [String], settings: PlayerSettings) async throws -> [String] {
        if lines.isEmpty { return [] }
        guard let key = SecureApiKeyStore.get(providerId: id), !key.isEmpty else {
            throw NetworkError.parseError("Gemini API Key가 없습니다.")
        }
        let models = (try? await listModels(key: key)) ?? ["gemini-2.5-flash", "gemini-2.0-flash"]
        var chain: [String] = []
        if !settings.geminiModel.isEmpty { chain.append(settings.geminiModel) }
        chain.append(contentsOf: models.filter { $0.localizedCaseInsensitiveContains("flash") })
        chain.append(contentsOf: models)
        let uniqueChain = Array(NSOrderedSet(array: chain)) as? [String] ?? chain

        var lastError: Error?
        for model in uniqueChain {
            do {
                return try await generate(key: key, model: model, lines: lines, settings: settings)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NetworkError.parseError("Gemini 번역에 실패했습니다.")
    }

    private func generate(key: String, model: String, lines: [String], settings: PlayerSettings) async throws -> [String] {
        let schema: [String: Any] = [
            "type": "ARRAY",
            "items": [
                "type": "OBJECT",
                "properties": [
                    "i": ["type": "INTEGER"],
                    "t": ["type": "STRING"]
                ],
                "required": ["i", "t"]
            ]
        ]
        let bodyObj: [String: Any] = [
            "system_instruction": [
                "parts": [["text": settings.translationSystemPrompt.isEmpty ? CloudTranslationPrompt.defaultSystemPrompt : settings.translationSystemPrompt]]
            ],
            "contents": [
                [
                    "role": "user",
                    "parts": [["text": CloudTranslationPrompt.userMessage(settings: settings, lines: lines)]]
                ]
            ],
            "generationConfig": [
                "responseMimeType": "application/json",
                "responseSchema": schema,
                "temperature": 0.3
            ]
        ]
        let payload = try JSONSerialization.data(withJSONObject: bodyObj)
        let encModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
        let url = "https://generativelanguage.googleapis.com/v1beta/models/\(encModel):generateContent"
        let (data, resp) = try await http.postData(url: url, body: payload, headers: ["x-goog-api-key": key])
        guard (200...299).contains(resp.statusCode) else {
            throw NetworkError.httpError(resp.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let candidates = root["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw NetworkError.parseError("Gemini 응답이 비어 있습니다.")
        }
        let text = parts.compactMap { part -> String? in
            if (part["thought"] as? Bool) == true { return nil }
            return part["text"] as? String
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return try CloudTranslationText.parseMarked(text, original: lines)
    }

    public func listModels(key: String) async throws -> [String] {
        let url = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200"
        let (data, resp) = try await http.getData(url: url, headers: ["x-goog-api-key": key])
        guard (200...299).contains(resp.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let arr = root["models"] as? [[String: Any]] else {
            throw NetworkError.httpError(resp.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        var models: [String] = []
        for m in arr {
            let rawName = (m["baseModelId"] as? String) ?? (m["name"] as? String) ?? ""
            let name = rawName.replacingOccurrences(of: "models/", with: "")
            guard name.lowercased().hasPrefix("gemini-") else { continue }
            let methods = (m["supportedGenerationMethods"] as? [String]) ?? ["generateContent"]
            guard methods.contains(where: { $0.caseInsensitiveCompare("generateContent") == .orderedSame }) else { continue }
            if name.range(of: "(?i)image|tts|audio|live|embedding|robotics|computer-use|exp", options: .regularExpression) == nil {
                models.append(name)
            }
        }
        return models
    }
}

/// iOS port of `OpenAITranslator`.
public final class OpenAITranslator: TranslationProvider {
    public let id = "openai"
    public let displayName = "OpenAI"
    private let http = HttpClient.shared

    public init() {}

    public func testConnection(settings: PlayerSettings) async throws -> String {
        guard let key = SecureApiKeyStore.get(providerId: id), !key.isEmpty else {
            throw NetworkError.parseError("OpenAI API Key가 없습니다. AI 설정에서 키를 저장하세요.")
        }
        let (data, resp) = try await http.getData(url: "https://api.openai.com/v1/models", headers: ["Authorization": "Bearer \(key)"])
        guard (200...299).contains(resp.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let arr = root["data"] as? [[String: Any]], !arr.isEmpty else {
            throw NetworkError.httpError(resp.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return "연결 성공: OpenAI API 인증 확인 (모델 \(arr.count)개)"
    }

    public func translateBatch(_ lines: [String], settings: PlayerSettings) async throws -> [String] {
        if lines.isEmpty { return [] }
        guard let key = SecureApiKeyStore.get(providerId: id), !key.isEmpty else {
            throw NetworkError.parseError("OpenAI API Key가 없습니다.")
        }
        let model = settings.openAIModel.isEmpty ? "gpt-4.1-mini" : settings.openAIModel
        let bodyObj: [String: Any] = [
            "model": model,
            "store": false,
            "instructions": settings.translationSystemPrompt.isEmpty ? CloudTranslationPrompt.defaultSystemPrompt : settings.translationSystemPrompt,
            "input": CloudTranslationPrompt.userMessage(settings: settings, lines: lines),
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "subtitles",
                    "strict": true,
                    "schema": CloudTranslationPrompt.objectSchema()
                ]
            ]
        ]
        let payload = try JSONSerialization.data(withJSONObject: bodyObj)
        let (data, resp) = try await http.postData(
            url: "https://api.openai.com/v1/responses",
            body: payload,
            headers: ["Authorization": "Bearer \(key)"]
        )
        guard (200...299).contains(resp.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NetworkError.httpError(resp.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        var text = (root["output_text"] as? String) ?? ""
        if text.isEmpty, let output = root["output"] as? [[String: Any]] {
            for item in output {
                if let content = item["content"] as? [[String: Any]] {
                    for part in content where (part["type"] as? String) == "output_text" {
                        text += (part["text"] as? String) ?? ""
                    }
                }
            }
        }
        return try CloudTranslationText.parseMarked(text, original: lines)
    }
}

/// iOS port of `DeepLTranslator`.
public final class DeepLTranslator: TranslationProvider {
    public let id = "deepl"
    public let displayName = "DeepL"
    private let http = HttpClient.shared

    public init() {}

    public func testConnection(settings: PlayerSettings) async throws -> String {
        guard let key = SecureApiKeyStore.get(providerId: id), !key.isEmpty else {
            throw NetworkError.parseError("DeepL API Key가 없습니다. AI 설정에서 키를 저장하세요.")
        }
        let endpoint = key.lowercased().hasSuffix(":fx")
            ? "https://api-free.deepl.com/v2/usage"
            : "https://api.deepl.com/v2/usage"
        let (data, resp) = try await http.getData(url: endpoint, headers: ["Authorization": "DeepL-Auth-Key \(key)"])
        guard (200...299).contains(resp.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw NetworkError.httpError(resp.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let used = (root["character_count"] as? Int) ?? 0
        let limit = (root["character_limit"] as? Int) ?? 0
        return "연결 성공: DeepL API 인증 확인 (사용량 \(used) / \(limit) 문자)"
    }

    public func translateBatch(_ lines: [String], settings: PlayerSettings) async throws -> [String] {
        if lines.isEmpty { return [] }
        guard let key = SecureApiKeyStore.get(providerId: id), !key.isEmpty else {
            throw NetworkError.parseError("DeepL API Key가 없습니다.")
        }
        let endpoint = key.lowercased().hasSuffix(":fx")
            ? "https://api-free.deepl.com/v2/translate"
            : "https://api.deepl.com/v2/translate"
        let bodyObj: [String: Any] = [
            "text": lines,
            "target_lang": "KO",
            "preserve_formatting": true,
            "context": String(settings.translationSystemPrompt.prefix(3000))
        ]
        let payload = try JSONSerialization.data(withJSONObject: bodyObj)
        let (data, resp) = try await http.postData(url: endpoint, body: payload, headers: ["Authorization": "DeepL-Auth-Key \(key)"])
        guard (200...299).contains(resp.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let arr = root["translations"] as? [[String: Any]],
              arr.count == lines.count else {
            throw NetworkError.httpError(resp.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return arr.compactMap { ($0["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

/// iOS port of `QwenTranslator` (DashScope International & China).
public final class QwenTranslator: TranslationProvider {
    public let id = "qwen"
    public let displayName = "Qwen"
    private let http = HttpClient.shared

    public init() {}

    public func testConnection(settings: PlayerSettings) async throws -> String {
        guard let key = SecureApiKeyStore.get(providerId: id), !key.isEmpty else {
            throw NetworkError.parseError("Qwen API Key가 없습니다. AI 설정에서 키를 저장하세요.")
        }
        let region = settings.qwenRegion == "china" ? "https://dashscope.aliyuncs.com" : "https://dashscope-intl.aliyuncs.com"
        let (data, resp) = try await http.getData(url: "\(region)/compatible-mode/v1/models", headers: ["Authorization": "Bearer \(key)"])
        guard (200...299).contains(resp.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let arr = root["data"] as? [[String: Any]] else {
            throw NetworkError.httpError(resp.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return "연결 성공: Qwen API 인증 확인 (모델 \(arr.count)개, \(settings.qwenRegion == "china" ? "China" : "International"))"
    }

    public func translateBatch(_ lines: [String], settings: PlayerSettings) async throws -> [String] {
        if lines.isEmpty { return [] }
        guard let key = SecureApiKeyStore.get(providerId: id), !key.isEmpty else {
            throw NetworkError.parseError("Qwen API Key가 없습니다.")
        }
        let region = settings.qwenRegion == "china" ? "https://dashscope.aliyuncs.com" : "https://dashscope-intl.aliyuncs.com"
        let model = settings.qwenModel.isEmpty ? "qwen-plus" : settings.qwenModel
        let bodyObj: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": settings.translationSystemPrompt.isEmpty ? CloudTranslationPrompt.defaultSystemPrompt : settings.translationSystemPrompt],
                ["role": "user", "content": CloudTranslationPrompt.userMessage(settings: settings, lines: lines)]
            ]
        ]
        let payload = try JSONSerialization.data(withJSONObject: bodyObj)
        let (data, resp) = try await http.postData(
            url: "\(region)/compatible-mode/v1/chat/completions",
            body: payload,
            headers: ["Authorization": "Bearer \(key)"]
        )
        guard (200...299).contains(resp.statusCode),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NetworkError.httpError(resp.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try CloudTranslationText.parseMarked(content, original: lines)
    }
}
