import Foundation
import Network
#if canImport(WebKit)
import WebKit
#endif

/// iOS port of `ReAnimeFlixCloud`, `ReAnimePlayerResolver`, and `FlixCloudHlsProxy`.
/// Uses `NWListener` on 127.0.0.1 to decrypt XOR-encoded FlixCloud HLS manifests and strip PNG/WEBP segment wrappers for `AVPlayer`.
public final class FlixCloudHlsProxy: @unchecked Sendable {
    public static let shared = FlixCloudHlsProxy()
    public static let defaultPkBase64 = "cebMPaA5RqAA4xO7OD97NjEuxtbAuHKev7kCh24guJw="

    private struct Session {
        let pkBase64: String
        let headers: [String: String]
        var lastAccess: Date
    }

    private let lock = NSLock()
    private var sessions: [String: Session] = [:]
    private var listener: NWListener?
    private var port: UInt16 = 0
    private let queue = DispatchQueue(label: "com.lilac.anime.flixproxy", attributes: .concurrent)

    private init() {}

    public func createProxyUrl(upstreamUrl: String, pkBase64: String, headers: String? = nil) -> String {
        ensureStarted()
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        lock.lock()
        sessions[id] = Session(pkBase64: pkBase64.trimmingCharacters(in: .whitespacesAndNewlines), headers: Self.parseHeaders(headers), lastAccess: Date())
        let currentPort = self.port
        lock.unlock()

        let encoded = Self.base64UrlEncode(Data(upstreamUrl.utf8))
        return "http://127.0.0.1:\(currentPort)/__flix/\(id)/\(encoded)"
    }

    public func clearSessions() {
        lock.lock()
        sessions.removeAll()
        lock.unlock()
    }

    private func ensureStarted() {
        lock.lock()
        if listener != nil && port > 0 {
            lock.unlock()
            return
        }
        lock.unlock()

        let semaphore = DispatchSemaphore(value: 0)
        do {
            let l = try NWListener(using: .tcp, on: .any)
            l.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case .ready = state, let actualPort = l.port?.rawValue {
                    self.lock.lock()
                    self.port = actualPort
                    self.lock.unlock()
                    semaphore.signal()
                } else if case .failed = state {
                    semaphore.signal()
                }
            }
            l.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            l.start(queue: queue)
            lock.lock()
            self.listener = l
            lock.unlock()
            _ = semaphore.wait(timeout: .now() + 3.0)
        } catch {
            // Listener failed
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            guard let self, let data, let requestText = String(data: data, encoding: .isoLatin1) else {
                connection.cancel()
                return
            }
            Task {
                await self.processHttpRequest(requestText: requestText, connection: connection)
            }
        }
    }

    private func processHttpRequest(requestText: String, connection: NWConnection) async {
        let firstLine = requestText.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else {
            sendHttpResponse(connection: connection, code: 400, contentType: "text/plain", body: Data("Bad Request".utf8))
            return
        }
        let method = parts[0].uppercased()
        guard method == "GET" || method == "HEAD" else {
            sendHttpResponse(connection: connection, code: 405, contentType: "text/plain", body: Data("Method Not Allowed".utf8))
            return
        }

        let path = parts[1].components(separatedBy: "?").first ?? parts[1]
        let segments = path.split(separator: "/").map(String.init)
        guard segments.count >= 3, segments[0] == "__flix" else {
            sendHttpResponse(connection: connection, code: 404, contentType: "text/plain", body: Data("Not Found".utf8))
            return
        }

        let sessionId = segments[1]
        let encodedUrl = segments.dropFirst(2).joined(separator: "/")

        lock.lock()
        guard var session = sessions[sessionId] else {
            lock.unlock()
            sendHttpResponse(connection: connection, code: 410, contentType: "text/plain", body: Data("Session expired".utf8))
            return
        }
        session.lastAccess = Date()
        sessions[sessionId] = session
        lock.unlock()

        guard let urlData = Self.base64UrlDecode(encodedUrl),
              let upstreamUrl = String(data: urlData, encoding: .utf8),
              !upstreamUrl.isEmpty else {
            sendHttpResponse(connection: connection, code: 400, contentType: "text/plain", body: Data("Bad target".utf8))
            return
        }

        let allowedHeaders: Set<String> = ["User-Agent", "Referer", "Origin", "Cookie", "Accept", "Accept-Language"]
        var forwardHeaders: [String: String] = [:]
        for (k, v) in session.headers where allowedHeaders.contains(k) && !v.isEmpty {
            forwardHeaders[k] = v
        }

        do {
            let (rawBody, httpResp) = try await HttpClient.shared.getData(url: upstreamUrl, headers: forwardHeaders)
            guard (200...299).contains(httpResp.statusCode) else {
                sendHttpResponse(connection: connection, code: httpResp.statusCode, contentType: "text/plain", body: rawBody)
                return
            }

            let kind = Self.responseKind(for: upstreamUrl)
            let decoded: Data
            switch kind {
            case .m3u8:
                decoded = try decodeManifest(body: rawBody, pkBase64: session.pkBase64, upstreamUrl: upstreamUrl, sessionId: sessionId)
            case .segment:
                decoded = decodeFragment(body: rawBody)
            case .key, .other:
                decoded = rawBody
            }

            let contentType: String = switch kind {
            case .m3u8: "application/vnd.apple.mpegurl"
            case .segment: "video/mp4"
            case .key: "application/octet-stream"
            case .other: httpResp.value(forHTTPHeaderField: "Content-Type") ?? "application/octet-stream"
            }

            sendHttpResponse(
                connection: connection,
                code: 200,
                contentType: contentType,
                body: method == "HEAD" ? Data() : decoded
            )
        } catch {
            sendHttpResponse(connection: connection, code: 502, contentType: "text/plain", body: Data("FLIX_DECODE_FAILED: \(error.localizedDescription)".utf8))
        }
    }

    private func sendHttpResponse(connection: NWConnection, code: Int, contentType: String, body: Data) {
        let reason: String = switch code {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 410: "Gone"
        default: "Bad Gateway"
        }
        let header = [
            "HTTP/1.1 \(code) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Access-Control-Allow-Origin: *",
            "Cache-Control: no-store",
            "Accept-Ranges: none",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var payload = Data(header.utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private enum ResponseKind { case m3u8, segment, key, other }

    private static func responseKind(for url: String) -> ResponseKind {
        let path = (URL(string: url)?.path ?? url.components(separatedBy: "?").first ?? "").lowercased()
        if path.hasSuffix(".m3u8") { return .m3u8 }
        if path.hasSuffix(".png") || path.hasSuffix(".webp") { return .segment }
        if path.hasSuffix("key.bin") { return .key }
        return .other
    }

    private func decodeManifest(body: Data, pkBase64: String, upstreamUrl: String, sessionId: String) throws -> Data {
        let raw = (String(data: body, encoding: .isoLatin1) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#EXTM3U") {
            return Data(rewriteManifest(manifest: raw, baseUrl: upstreamUrl, sessionId: sessionId).utf8)
        }
        guard let encrypted = Data(base64Encoded: raw, options: .ignoreUnknownCharacters),
              let pk = Data(base64Encoded: pkBase64.trimmingCharacters(in: .whitespacesAndNewlines), options: .ignoreUnknownCharacters),
              !pk.isEmpty else {
            throw NetworkError.parseError("M3U8 또는 __pk Base64 디코딩 실패")
        }
        let pkBytes = [UInt8](pk)
        var plainBytes = [UInt8](encrypted)
        for i in 0..<plainBytes.count {
            plainBytes[i] ^= pkBytes[i % pkBytes.count]
        }
        let manifest = String(decoding: plainBytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard manifest.hasPrefix("#EXTM3U") else {
            throw NetworkError.parseError("M3U8 복호화 결과가 유효하지 않습니다.")
        }
        return Data(rewriteManifest(manifest: manifest, baseUrl: upstreamUrl, sessionId: sessionId).utf8)
    }

    private func rewriteManifest(manifest: String, baseUrl: String, sessionId: String) -> String {
        lock.lock()
        let currentPort = self.port
        lock.unlock()

        func toProxy(_ url: String) -> String {
            let encoded = Self.base64UrlEncode(Data(url.utf8))
            return "http://127.0.0.1:\(currentPort)/__flix/\(sessionId)/\(encoded)"
        }

        return manifest.components(separatedBy: .newlines).map { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                if trimmed.lowercased().contains("uri=\"") {
                    guard let regex = try? NSRegularExpression(pattern: "URI=\"([^\"]+)\"", options: .caseInsensitive) else {
                        return line
                    }
                    var updated = line
                    let matches = regex.matches(in: updated, range: NSRange(updated.startIndex..., in: updated)).reversed()
                    for match in matches {
                        if let r = Range(match.range(at: 1), in: updated),
                           let full = Range(match.range, in: updated) {
                            let resolved = HTMLParser.resolveURL(String(updated[r]), base: baseUrl)
                            updated.replaceSubrange(full, with: "URI=\"\(toProxy(resolved))\"")
                        }
                    }
                    return updated
                }
                return line
            } else {
                let resolved = HTMLParser.resolveURL(trimmed, base: baseUrl)
                return toProxy(resolved)
            }
        }.joined(separator: "\n")
    }

    private func decodeFragment(body: Data) -> Data {
        let bytes = [UInt8](body)
        var payloadSlice: ArraySlice<UInt8>? = nil

        if bytes.count >= 12 &&
            bytes[0] == UInt8(ascii: "R") && bytes[1] == UInt8(ascii: "I") &&
            bytes[2] == UInt8(ascii: "F") && bytes[3] == UInt8(ascii: "F") &&
            bytes[8] == UInt8(ascii: "W") && bytes[9] == UInt8(ascii: "E") &&
            bytes[10] == UInt8(ascii: "B") && bytes[11] == UInt8(ascii: "P") {
            payloadSlice = bytes[12...]
        } else if bytes.count >= 8 &&
            bytes[0] == 137 && bytes[1] == 80 && bytes[2] == 78 && bytes[3] == 71 &&
            bytes[4] == 13 && bytes[5] == 10 && bytes[6] == 26 && bytes[7] == 10 {
            payloadSlice = bytes[8...]
        }

        guard let slice = payloadSlice else { return body }
        var payload = Array(slice)
        if payload.isEmpty || payload[0] == UInt8(ascii: "G") {
            return Data(payload)
        }
        let key: [UInt8] = [157, 42, 241, 71, 179, 142, 92, 112, 166, 25, 228, 59, 216, 98, 15, 197]
        for i in 0..<payload.count {
            payload[i] ^= key[i % key.count]
        }
        return Data(payload)
    }

    public static func parseHeaders(_ raw: String?) -> [String: String] {
        guard let raw, !raw.isEmpty else { return [:] }
        var map: [String: String] = [:]
        for line in raw.components(separatedBy: .newlines) {
            if let idx = line.firstIndex(of: ":") {
                let k = line[..<idx].trimmingCharacters(in: .whitespaces)
                let v = line[line.index(after: idx)...].trimmingCharacters(in: .whitespaces)
                if !k.isEmpty && !v.isEmpty {
                    map[k] = v
                }
            }
        }
        return map
    }

    public static func base64UrlEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func base64UrlDecode(_ str: String) -> Data? {
        var b64 = str
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let rem = b64.count % 4
        if rem > 0 {
            b64.append(String(repeating: "=", count: 4 - rem))
        }
        return Data(base64Encoded: b64)
    }
}

#if canImport(WebKit)
/// Headless WKWebView bootstrap for Re:Anime FlixCloud WASM key derivation.
@MainActor
public final class ReAnimeFlixCloudBootstrapper: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<LinkkfApiClient.ResolvedPlayerResult, Never>?
    private var pollTimer: Timer?
    private var injected = false
    private var preparedUrl = ""
    private var episodeId = ""

    public static func resolve(episode: Episode, anilistId: Int?) async -> LinkkfApiClient.ResolvedPlayerResult {
        guard let aid = anilistId, aid > 0, episode.number > 0 else {
            return LinkkfApiClient.ResolvedPlayerResult(episodeId: episode.id, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: nil)
        }
        guard let flixUrl = await ReAnimeHarClient().resolveFlixUrl(anilistId: aid, episode: episode.number) else {
            return LinkkfApiClient.ResolvedPlayerResult(episodeId: episode.id, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: nil)
        }
        let bootstrapper = ReAnimeFlixCloudBootstrapper()
        return await bootstrapper.run(episodeId: episode.id, flixUrl: flixUrl)
    }

    private func run(episodeId: String, flixUrl: String) async -> LinkkfApiClient.ResolvedPlayerResult {
        self.episodeId = episodeId
        self.preparedUrl = Self.prepareUrl(flixUrl)
        return await withCheckedContinuation { cont in
            self.continuation = cont
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default()
            let wv = WKWebView(frame: .zero, configuration: config)
            wv.customUserAgent = HttpClient.mobileUserAgent
            wv.navigationDelegate = self
            self.webView = wv

            if let url = URL(string: preparedUrl) {
                var req = URLRequest(url: url)
                req.setValue("https://reanime.to/", forHTTPHeaderField: "Referer")
                wv.load(req)
                startTimeout()
            } else {
                finish(LinkkfApiClient.ResolvedPlayerResult(episodeId: episodeId, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: nil))
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !injected, webView.url?.host?.lowercased().contains("flixcloud.cc") == true else { return }
        injected = true
        webView.evaluateJavaScript(Self.bootstrapScript, completionHandler: nil)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollResult()
            }
        }
    }

    private func startTimeout() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 35_000_000_000)
            if continuation != nil {
                finish(LinkkfApiClient.ResolvedPlayerResult(episodeId: episodeId, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: preparedUrl))
            }
        }
    }

    private func pollResult() {
        guard let webView else { return }
        webView.evaluateJavaScript("window.__lilacReAnimeFlixResult || ''") { [weak self] raw, _ in
            guard let self, let str = raw as? String, !str.isEmpty else { return }
            guard let data = str.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            if (obj["ok"] as? Bool) == true,
               let m3u8 = obj["m3u8"] as? String, !m3u8.isEmpty,
               let pk = obj["pk"] as? String, !pk.isEmpty {
                let headers = "User-Agent: \(HttpClient.mobileUserAgent)\nReferer: https://flixcloud.cc/\nOrigin: https://flixcloud.cc"
                let proxyUrl = FlixCloudHlsProxy.shared.createProxyUrl(upstreamUrl: m3u8, pkBase64: pk, headers: headers)
                self.finish(LinkkfApiClient.ResolvedPlayerResult(
                    episodeId: self.episodeId,
                    m3u8Url: proxyUrl,
                    referer: "https://flixcloud.cc/",
                    headers: headers,
                    subtitleUrl: nil,
                    subtitleReferer: nil,
                    playerUrl: self.preparedUrl,
                    flixCloudPk: pk
                ))
            } else {
                self.finish(LinkkfApiClient.ResolvedPlayerResult(episodeId: self.episodeId, m3u8Url: nil, referer: nil, headers: nil, subtitleUrl: nil, subtitleReferer: nil, playerUrl: self.preparedUrl))
            }
        }
    }

    private func finish(_ result: LinkkfApiClient.ResolvedPlayerResult) {
        pollTimer?.invalidate()
        pollTimer = nil
        webView?.stopLoading()
        webView = nil
        if let cont = continuation {
            continuation = nil
            cont.resume(returning: result)
        }
    }

    private static func prepareUrl(_ raw: String) -> String {
        guard var comp = URLComponents(string: raw) else { return raw }
        var items = comp.queryItems ?? []
        func ensure(_ k: String, _ v: String) {
            if !items.contains(where: { $0.name == k }) {
                items.append(URLQueryItem(name: k, value: v))
            }
        }
        ensure("autoPlay", "true")
        ensure("skI", "false")
        ensure("skO", "false")
        ensure("start_at", "0")
        ensure("project_r_ts", String(Int64(Date().timeIntervalSince1970 * 1000)))
        comp.queryItems = items
        return comp.url?.absoluteString ?? raw
    }

    private static let bootstrapScript = """
    (function(){
      if(window.__lilacReAnimeFlixStarted)return;
      window.__lilacReAnimeFlixStarted=true;
      window.__lilacReAnimeFlixResult='';
      const fail=(e)=>{window.__lilacReAnimeFlixResult=JSON.stringify({ok:false,error:String(e&&e.message||e)});};
      const esc=s=>String(s).replace(/[.*+?^$()|[\\]\\\\]/g,'\\\\$&');
      const get=(html,key)=>{const m=html.match(new RegExp('(?:["\\']?)'+esc(key)+'(?:["\\']?)\\\\s*:\\\\s*["\\']([^"\\']*)["\\']'));return m?m[1]:null};
      const b64=s=>{const x=atob(String(s).replace(/-/g,'+').replace(/_/g,'/'));const a=new Uint8Array(x.length);for(let i=0;i<x.length;i++)a[i]=x.charCodeAt(i);return a};
      const b64s=a=>{let s='';for(let i=0;i<a.length;i+=0x8000)s+=String.fromCharCode.apply(null,a.subarray(i,Math.min(i+0x8000,a.length)));return btoa(s)};
      const sha=async s=>{const d=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s));return Array.from(new Uint8Array(d)).map(x=>x.toString(16).padStart(2,'0')).join('')};
      (async()=>{
        try{
          const html=document.documentElement.innerHTML;
          const seed=get(html,'obfuscation_seed');
          const payload=get(html,'w_payload');
          if(!seed||!payload)throw new Error('embedded data missing');
          let e=seed;for(let i=0;i<3;i++)e=await sha(e+i);let a=e;for(let i=0;i<3;i++)a=await sha(a+i);
          const names={videoField:'vf_'+e.substring(0,8),keyField:'kf_'+e.substring(8,16),ivField:'ivf_'+e.substring(16,24),tokenField:e.substring(48,64)+'_'+e.substring(56,64),keyFrag2Field:a.substring(0,16)+'_'+a.substring(16,24)};
          const frag=get(html,names.keyField),iv=get(html,names.ivField),key2=get(html,names.keyFrag2Field),token=get(html,names.tokenField);
          if(!frag||!iv||!key2||!token)throw new Error('crypto fields missing');
          const api=await fetch('/api/m3u8/'+encodeURIComponent(token),{credentials:'same-origin'});if(!api.ok)throw new Error('token HTTP '+api.status);const w=await api.json();
          const vf=await sha(token+'vid');const kf=await sha(token+'key');const E=w[vf.substring(0,10)],Y=w[kf.substring(0,10)];if(!E||!Y)throw new Error('token fields missing');
          const wasm=b64(payload), inst=(await WebAssembly.instantiate(wasm,{})).instance, ex=inst.exports, mem=ex.memory;if(mem.buffer.byteLength===0)mem.grow(1);const bytes=new Uint8Array(mem.buffer);
          const t=b64(frag), k=b64(key2), y=b64(Y), n=t.length, p1=1000,p2=p1+n,p3=p2+n,p4=p3+n;bytes.set(t,p1);bytes.set(k,p2);bytes.set(y,p3);ex._s(parseInt(seed.substring(0,8),16));ex._r(p1,p2,p3,p4,n);
          const H=new Uint8Array(ex.memory.buffer).slice(p4,p4+n);
          const pkPtr=ex._c(), pkBytes=new Uint8Array(ex.memory.buffer).slice(pkPtr,pkPtr+32), pk=b64s(pkBytes);
          const base=await crypto.subtle.importKey('raw',H,{name:'PBKDF2'},false,['deriveBits']);const bits=await crypto.subtle.deriveBits({name:'PBKDF2',salt:new TextEncoder().encode(seed),iterations:1000,hash:'SHA-256'},base,256);const J=new Uint8Array(bits);for(let i=0;i<32;i++)J[i]^=seed.charCodeAt(i%seed.length);
          const digest=new Uint8Array(await crypto.subtle.digest('SHA-256',J));const aes=await crypto.subtle.importKey('raw',digest,{name:'AES-CBC'},false,['decrypt']);const plain=await crypto.subtle.decrypt({name:'AES-CBC',iv:b64(iv)},aes,b64(E));const m3u8=new TextDecoder().decode(plain).trim();if(!m3u8)throw new Error('empty HLS URL');
          window.__lilacReAnimeFlixResult=JSON.stringify({ok:true,m3u8:m3u8,pk:pk});
        }catch(e){fail(e)}
      })();
    })();
    """
}
#endif
