import SwiftUI
import UniformTypeIdentifiers

/// iOS port of `SettingsScreen.kt` and `AiSettingsScreen.kt`.
public struct SettingsScreen: View {
    @ObservedObject public var vm: AnimeViewModel

    @State private var showAiSettings: Bool = false

    public var body: some View {
        NavigationStack {
            Form {
                Section("외관 및 테마") {
                    Picker("테마 모드", selection: Binding(
                        get: { vm.themeMode },
                        set: { vm.setThemeMode($0) }
                    )) {
                        ForEach(ThemeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                Section("영상 및 자막 소스") {
                    Picker("기본 영상 소스", selection: Binding(
                        get: { vm.playerSettings.videoSourcePreference },
                        set: { val in
                            var s = vm.playerSettings
                            s.videoSourcePreference = val
                            vm.updatePlayerSettings(s)
                        }
                    )) {
                        Text("LinkKF (linkani.tv)").tag("linkkf")
                        Text("Re:ANIME (reanime.to)").tag("reanime")
                        Text("Miruro (miruro.cx)").tag("miruro")
                        Text("애니24 (ohli24.com)").tag("ohli24")
                    }

                    Picker("우선 자막 소스", selection: Binding(
                        get: { vm.playerSettings.subtitleSourcePreference },
                        set: { val in
                            var s = vm.playerSettings
                            s.subtitleSourcePreference = val
                            vm.updatePlayerSettings(s)
                        }
                    )) {
                        Text("LinkKF 내장 VTT").tag("linkkf")
                        Text("Re:Anime 트랙").tag("reanime")
                        Text("Jimaku (일본어 ASS/SRT)").tag("jimaku")
                        Text("Anissia (한국어 팬자막)").tag("anissia")
                    }
                }

                Section("AI 자막 번역 & 온디바이스 모델") {
                    NavigationLink {
                        AiSettingsScreen(vm: vm)
                    } label: {
                        HStack {
                            Image(systemName: "cpu.fill")
                                .foregroundStyle(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI 번역 · 로컬 GGUF · Whisper 설정")
                                    .font(.subheadline.weight(.semibold))
                                Text("현재 제공자: \(vm.playerSettings.translationProvider.uppercased())")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("플레이어 재생 및 스킵") {
                    Toggle("다음 회차 자동 재생", isOn: Binding(
                        get: { vm.playerSettings.autoPlay },
                        set: { val in
                            var s = vm.playerSettings
                            s.autoPlay = val
                            vm.updatePlayerSettings(s)
                        }
                    ))
                    Toggle("OP/ED 구간 스킵 버튼 표시", isOn: Binding(
                        get: { vm.playerSettings.showChapterSkipButton },
                        set: { val in
                            var s = vm.playerSettings
                            s.showChapterSkipButton = val
                            vm.updatePlayerSettings(s)
                        }
                    ))
                    Toggle("OP/ED 자동 건너뛰기", isOn: Binding(
                        get: { vm.playerSettings.autoSkip },
                        set: { val in
                            var s = vm.playerSettings
                            s.autoSkip = val
                            vm.updatePlayerSettings(s)
                        }
                    ))
                    Toggle("앰비언트 조명 효과", isOn: Binding(
                        get: { vm.playerSettings.ambientModeEnabled },
                        set: { val in
                            var s = vm.playerSettings
                            s.ambientModeEnabled = val
                            vm.updatePlayerSettings(s)
                        }
                    ))
                }

                Section("자막 스타일") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("자막 크기")
                            Spacer()
                            Text("\(Int(vm.playerSettings.subtitleSize))%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(vm.playerSettings.subtitleSize) },
                            set: { val in
                                var s = vm.playerSettings
                                s.subtitleSize = Float(val)
                                vm.updatePlayerSettings(s)
                            }
                        ), in: 60...180, step: 5)
                        .tint(.purple)
                    }

                    Toggle("굵은 자막 글꼴 (Bold)", isOn: Binding(
                        get: { vm.playerSettings.vttBold },
                        set: { val in
                            var s = vm.playerSettings
                            s.vttBold = val
                            vm.updatePlayerSettings(s)
                        }
                    ))
                }

                Section("고급 비디오 필터 (Metal 셰이더)") {
                    Toggle("Anime4K 실시간 업스케일링", isOn: Binding(
                        get: { vm.playerSettings.aiUpscalingEnabled },
                        set: { val in
                            var s = vm.playerSettings
                            s.aiUpscalingEnabled = val
                            vm.updatePlayerSettings(s)
                        }
                    ))
                    Picker("Anime4K 모드", selection: Binding(
                        get: { vm.playerSettings.aiUpscalingMode },
                        set: { val in
                            var s = vm.playerSettings
                            s.aiUpscalingMode = val
                            vm.updatePlayerSettings(s)
                        }
                    )) {
                        Text("모드 A").tag("A")
                        Text("모드 B").tag("B")
                        Text("모드 C").tag("C")
                        Text("모드 A+A").tag("A+A")
                        Text("모드 B+B").tag("B+B")
                        Text("모드 C+A").tag("C+A")
                    }
                    Toggle("하드섭(박힌 자막) 지우기", isOn: Binding(
                        get: { vm.playerSettings.subtitleEraseEnabled },
                        set: { val in
                            var s = vm.playerSettings
                            s.subtitleEraseEnabled = val
                            vm.updatePlayerSettings(s)
                        }
                    ))
                    Toggle("워터마크 제거 (Delogo)", isOn: Binding(
                        get: { vm.playerSettings.watermarkRemovalEnabled },
                        set: { val in
                            var s = vm.playerSettings
                            s.watermarkRemovalEnabled = val
                            vm.updatePlayerSettings(s)
                        }
                    ))
                }

                Section("앱 정보") {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text("0.4.1 (Build 31 · iOS Port)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("설정")
        }
    }
}

/// iOS port of `AiSettingsScreen.kt` (Cloud API Keys, Local GGUF Hub, Whisper ggml Models, Prompt & Sampling Parameters, and Subtitle File Translation Test).
public struct AiSettingsScreen: View {
    @ObservedObject public var vm: AnimeViewModel

    @State private var geminiKey: String = SecureApiKeyStore.get(providerId: "gemini") ?? ""
    @State private var openAIKey: String = SecureApiKeyStore.get(providerId: "openai") ?? ""
    @State private var deepLKey: String = SecureApiKeyStore.get(providerId: "deepl") ?? ""
    @State private var qwenKey: String = SecureApiKeyStore.get(providerId: "qwen") ?? ""

    @State private var hfRepoQuery: String = "ggml-org/gemma-4-E2B-it-GGUF"
    @State private var hfSearchResults: [LocalAiTranslationRuntime.GgufModelInfo] = []
    @State private var installedGgufModels: [LocalAiTranslationRuntime.GgufModelInfo] = LocalAiTranslationRuntime.shared.listInstalledModels()
    @State private var isSearchingHf: Bool = false
    @State private var ggufDownloadProgress: [String: Double] = [:]

    @State private var whisperDownloadProgress: [String: Int] = [:]
    @State private var statusBanner: String? = nil
    @State private var isTestingProvider: Bool = false
    @State private var sampleTestInput: String = "こんにちは。今日はいい天気ですね。"
    @State private var sampleTestOutput: String = ""

    @State private var showSubtitleImporterForTranslation: Bool = false
    @State private var fileTranslationProgress: String? = nil

    public var body: some View {
        Form {
            if let banner = statusBanner {
                Section {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.purple)
                }
            }

            Section("1. 번역 제공자 선택") {
                Picker("AI 번역 제공자", selection: Binding(
                    get: { vm.playerSettings.translationProvider },
                    set: { val in
                        var s = vm.playerSettings
                        s.translationProvider = val
                        vm.updatePlayerSettings(s)
                    }
                )) {
                    Text("로컬 AI (온디바이스 GGUF)").tag("local")
                    Text("Google Gemini").tag("gemini")
                    Text("OpenAI (GPT-4.1 / GPT-5)").tag("openai")
                    Text("Alibaba Qwen (DashScope)").tag("qwen")
                    Text("DeepL API").tag("deepl")
                }

                Toggle("플레이어 자막 자동 AI 번역", isOn: Binding(
                    get: { vm.playerSettings.translationAutoEnabled },
                    set: { val in
                        var s = vm.playerSettings
                        s.translationAutoEnabled = val
                        vm.updatePlayerSettings(s)
                    }
                ))
            }

            Section("2. 로컬 AI (GGUF 모델 허브 — 추천: Gemma 4 E2B Q4_0)") {
                HStack {
                    TextField("HuggingFace 저장소 (예: ggml-org/gemma-4-E2B-it-GGUF)", text: $hfRepoQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("검색") {
                        searchHuggingFace()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(isSearchingHf)
                }

                if isSearchingHf {
                    ProgressView("HuggingFace GGUF 파일 목록 조회 중...")
                }

                ForEach(hfSearchResults) { model in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.fileName)
                                .font(.caption.bold())
                            Text("\(model.quantization) · \(formatBytes(model.sizeBytes))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let prog = ggufDownloadProgress[model.fileName], prog < 1.0 {
                            ProgressView(value: prog)
                                .frame(width: 70)
                        } else if installedGgufModels.contains(where: { $0.fileName == model.fileName }) {
                            Text("설치됨")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        } else {
                            Button("다운로드") {
                                downloadGguf(model)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if !installedGgufModels.isEmpty {
                    Picker("사용할 설치된 GGUF 모델", selection: Binding(
                        get: { vm.playerSettings.translationModelId ?? installedGgufModels.first?.fileName ?? "" },
                        set: { val in
                            var s = vm.playerSettings
                            s.translationModelId = val
                            vm.updatePlayerSettings(s)
                        }
                    )) {
                        ForEach(installedGgufModels) { m in
                            Text(m.fileName).tag(m.fileName)
                        }
                    }
                }
            }

            Section("3. 클라우드 AI 설정 (Keychain 안전 저장)") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Gemini API Key")
                        .font(.caption.bold())
                    SecureField("AIza...", text: $geminiKey)
                        .textInputAutocapitalization(.never)
                    TextField("Gemini 모델 (기본: gemini-2.5-flash)", text: Binding(
                        get: { vm.playerSettings.geminiModel },
                        set: { var s = vm.playerSettings; s.geminiModel = $0; vm.updatePlayerSettings(s) }
                    ))
                    .font(.caption)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenAI API Key")
                        .font(.caption.bold())
                    SecureField("sk-...", text: $openAIKey)
                        .textInputAutocapitalization(.never)
                    TextField("OpenAI 모델 (기본: gpt-4.1-mini)", text: Binding(
                        get: { vm.playerSettings.openAIModel },
                        set: { var s = vm.playerSettings; s.openAIModel = $0; vm.updatePlayerSettings(s) }
                    ))
                    .font(.caption)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Qwen (DashScope) API Key")
                        .font(.caption.bold())
                    SecureField("sk-...", text: $qwenKey)
                        .textInputAutocapitalization(.never)
                    Picker("Qwen 지역", selection: Binding(
                        get: { vm.playerSettings.qwenRegion },
                        set: { var s = vm.playerSettings; s.qwenRegion = $0; vm.updatePlayerSettings(s) }
                    )) {
                        Text("International (dashscope-intl)").tag("international")
                        Text("China (dashscope.aliyuncs)").tag("china")
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("DeepL API Key")
                        .font(.caption.bold())
                    SecureField("DeepL Auth Key (:fx 지원)", text: $deepLKey)
                        .textInputAutocapitalization(.never)
                }

                HStack {
                    Button("API 키 저장") {
                        SecureApiKeyStore.set(providerId: "gemini", apiKey: geminiKey)
                        SecureApiKeyStore.set(providerId: "openai", apiKey: openAIKey)
                        SecureApiKeyStore.set(providerId: "qwen", apiKey: qwenKey)
                        SecureApiKeyStore.set(providerId: "deepl", apiKey: deepLKey)
                        statusBanner = "API 키가 iOS Keychain에 안전하게 저장되었습니다."
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)

                    Spacer()

                    Button("현재 제공자 연결 테스트") {
                        testCurrentProvider()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTestingProvider)
                }
            }

            Section("4. 프롬프트 및 로컬 AI 추론 옵션") {
                Picker("Thinking (추론 토큰)", selection: Binding(
                    get: { vm.playerSettings.aiThinkingMode },
                    set: { var s = vm.playerSettings; s.aiThinkingMode = $0; vm.updatePlayerSettings(s) }
                )) {
                    Text("OFF (권장 — 응답 지연 최소화)").tag("off")
                    Text("ON").tag("on")
                    Text("AUTO").tag("auto")
                }

                Stepper("Context Size: \(vm.playerSettings.aiContextSize) tokens", value: Binding(
                    get: { vm.playerSettings.aiContextSize },
                    set: { var s = vm.playerSettings; s.aiContextSize = $0; vm.updatePlayerSettings(s) }
                ), in: 1024...16384, step: 1024)

                Stepper("Max Tokens: \(vm.playerSettings.aiMaxTokens)", value: Binding(
                    get: { vm.playerSettings.aiMaxTokens },
                    set: { var s = vm.playerSettings; s.aiMaxTokens = $0; vm.updatePlayerSettings(s) }
                ), in: 128...2048, step: 128)

                Stepper("문맥 자막 수 (Context Cues): \(vm.playerSettings.aiContextCues)개", value: Binding(
                    get: { vm.playerSettings.aiContextCues },
                    set: { var s = vm.playerSettings; s.aiContextCues = $0; vm.updatePlayerSettings(s) }
                ), in: 0...10)

                VStack(alignment: .leading, spacing: 4) {
                    Text("시스템 프롬프트")
                        .font(.caption.bold())
                    TextEditor(text: Binding(
                        get: { vm.playerSettings.translationSystemPrompt },
                        set: { var s = vm.playerSettings; s.translationSystemPrompt = $0; vm.updatePlayerSettings(s) }
                    ))
                    .frame(minHeight: 80)
                    .font(.caption)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("사용자 프롬프트 ({context}, {future_context}, {source_text})")
                        .font(.caption.bold())
                    TextEditor(text: Binding(
                        get: { vm.playerSettings.translationPrompt },
                        set: { var s = vm.playerSettings; s.translationPrompt = $0; vm.updatePlayerSettings(s) }
                    ))
                    .frame(minHeight: 80)
                    .font(.caption)
                }
            }

            Section("5. Whisper 일본어 음성 → SRT 자막 추출 모델") {
                ForEach(WhisperTranscriptionService.modelOptions) { opt in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(opt.title)
                                .font(.subheadline.weight(.medium))
                            Text(opt.note)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let prog = whisperDownloadProgress[opt.id], prog < 100 {
                            Text("\(prog)%")
                                .font(.caption.monospacedDigit())
                        } else if WhisperTranscriptionService.shared.isModelInstalled(id: opt.id) {
                            Button(WhisperTranscriptionService.shared.selectedModelId == opt.id ? "선택됨" : "선택") {
                                WhisperTranscriptionService.shared.selectedModelId = opt.id
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(WhisperTranscriptionService.shared.selectedModelId == opt.id ? .green : .purple)
                        } else {
                            Button("설치") {
                                downloadWhisperModel(opt.id)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("6. 자막 문장 및 파일 번역 테스트") {
                TextField("테스트할 일본어/영어 문장", text: $sampleTestInput)
                Button("문장 번역 테스트 실행") {
                    runSampleTranslation()
                }
                .disabled(isTestingProvider)

                if !sampleTestOutput.isEmpty {
                    Text("결과: \(sampleTestOutput)")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }

                Button {
                    showSubtitleImporterForTranslation = true
                } label: {
                    Label("자막 파일(.srt/.ass/.smi) 전체 번역 및 내보내기", systemImage: "doc.badge.gearshape")
                }

                if let fileProg = fileTranslationProgress {
                    Text(fileProg)
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
        }
        .navigationTitle("AI 자막 번역 설정")
        .fileImporter(
            isPresented: $showSubtitleImporterForTranslation,
            allowedContentTypes: [.item, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                translateSelectedSubtitleFile(url)
            }
        }
    }

    private func searchHuggingFace() {
        isSearchingHf = true
        Task {
            let results = (try? await LocalAiTranslationRuntime.shared.searchHuggingFaceModels(repoId: hfRepoQuery)) ?? []
            await MainActor.run {
                self.hfSearchResults = results
                self.isSearchingHf = false
            }
        }
    }

    private func downloadGguf(_ model: LocalAiTranslationRuntime.GgufModelInfo) {
        ggufDownloadProgress[model.fileName] = 0.01
        Task {
            do {
                _ = try await LocalAiTranslationRuntime.shared.downloadGgufModel(model) { prog in
                    Task { @MainActor in
                        self.ggufDownloadProgress[model.fileName] = prog
                    }
                }
                await MainActor.run {
                    self.installedGgufModels = LocalAiTranslationRuntime.shared.listInstalledModels()
                    self.statusBanner = "\(model.fileName) 다운로드 완료!"
                }
            } catch {
                await MainActor.run {
                    self.ggufDownloadProgress.removeValue(forKey: model.fileName)
                    self.statusBanner = "GGUF 다운로드 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    private func downloadWhisperModel(_ id: String) {
        whisperDownloadProgress[id] = 1
        Task {
            do {
                _ = try await WhisperTranscriptionService.shared.downloadModel(id: id) { prog in
                    Task { @MainActor in
                        self.whisperDownloadProgress[id] = prog
                    }
                }
                await MainActor.run {
                    WhisperTranscriptionService.shared.selectedModelId = id
                    self.statusBanner = "Whisper \(id) 모델 설치 완료"
                }
            } catch {
                await MainActor.run {
                    self.whisperDownloadProgress.removeValue(forKey: id)
                    self.statusBanner = "Whisper 다운로드 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    private func testCurrentProvider() {
        isTestingProvider = true
        Task {
            let provider = TranslationManager.shared.createProvider(id: vm.playerSettings.translationProvider)
            do {
                let msg = try await provider.testConnection(settings: vm.playerSettings)
                await MainActor.run {
                    self.statusBanner = msg
                    self.isTestingProvider = false
                }
            } catch {
                await MainActor.run {
                    self.statusBanner = "연결 실패: \(error.localizedDescription)"
                    self.isTestingProvider = false
                }
            }
        }
    }

    private func runSampleTranslation() {
        isTestingProvider = true
        Task {
            do {
                let res = try await TranslationManager.shared.translateBatchWithFallback(lines: [sampleTestInput], settings: vm.playerSettings)
                await MainActor.run {
                    self.sampleTestOutput = res.first ?? ""
                    self.isTestingProvider = false
                }
            } catch {
                await MainActor.run {
                    self.sampleTestOutput = "오류: \(error.localizedDescription)"
                    self.isTestingProvider = false
                }
            }
        }
    }

    private func translateSelectedSubtitleFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        fileTranslationProgress = "번역 준비 중..."
        Task {
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let outURL = try await TranslationManager.shared.translateSubtitleFile(at: url, settings: vm.playerSettings) { done, total in
                    Task { @MainActor in
                        self.fileTranslationProgress = "자막 번역 중... (\(done) / \(total) 대사)"
                    }
                }
                await MainActor.run {
                    self.fileTranslationProgress = "번역 완료! 저장 위치: \(outURL.lastPathComponent)"
                }
            } catch {
                await MainActor.run {
                    self.fileTranslationProgress = "파일 번역 실패: \(error.localizedDescription)"
                }
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024.0 * 1024.0)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024.0)
        }
        return String(format: "%.0f MB", mb)
    }
}
