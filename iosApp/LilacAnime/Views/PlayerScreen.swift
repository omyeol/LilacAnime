import SwiftUI
import AVKit
import UniformTypeIdentifiers

/// iOS port of `PlayerScreen.kt`, `MpvPlayerEngine.kt`, `LibassTranslationOverlay.kt`, and `WatermarkRegionPicker.kt`.
public struct PlayerScreen: View {
    @ObservedObject public var vm: AnimeViewModel
    public let anime: Anime
    @State public var currentEpisode: Episode
    public let onDismiss: () -> Void

    @State private var player = AVPlayer()
    @State private var isPlaying: Bool = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var showControls: Bool = true
    @State private var isResolvingStream: Bool = true
    @State private var streamError: String? = nil

    // Subtitles & Real-time AI Translation
    @State private var subtitleCues: [SubtitleCue] = []
    @State private var activeCueText: String = ""
    @State private var availableSubtitles: [SubtitleDiscoveryService.SubtitleOption] = []
    @State private var selectedSubtitleOption: SubtitleDiscoveryService.SubtitleOption? = nil
    @State private var showSubtitleSheet: Bool = false
    @State private var showLocalFileImporter: Bool = false
    @State private var isTranslatingRealtime: Bool = false
    @State private var translationTask: Task<Void, Never>? = nil

    // AniSkip OP/ED Segments
    @State private var skipSegments: [ChapterSkipSegment] = []
    @State private var activeSkipSegment: ChapterSkipSegment? = nil

    // Filter & Region Picker (Anime4K / Hard-Sub Erase / Watermark Masking)
    @State private var showFilterSheet: Bool = false
    @State private var isPickingEraseRegion: Bool = false
    @State private var isPickingWatermarkRegion: Bool = false
    @State private var dragStart: CGPoint? = nil
    @State private var dragCurrent: CGPoint? = nil

    @State private var timeObserverToken: Any? = nil

    public init(vm: AnimeViewModel, anime: Anime, episode: Episode, onDismiss: @escaping () -> Void) {
        self.vm = vm
        self.anime = anime
        self._currentEpisode = State(initialValue: episode)
        self.onDismiss = onDismiss
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Ambient Mode Glow
                if vm.playerSettings.ambientModeEnabled {
                    LilacRemoteImage(url: anime.backdrop.isEmpty ? anime.poster : anime.backdrop)
                        .blur(radius: 55)
                        .opacity(0.45)
                        .ignoresSafeArea()
                }

                // Video Player Surface
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showControls.toggle()
                        }
                    }
                    .gesture(
                        SpatialTapGesture(count: 2)
                            .onEnded { event in
                                let seekSec = Double(vm.playerSettings.doubleTapSeekSeconds)
                                if event.location.x < geo.size.width / 2 {
                                    seek(by: -seekSec)
                                } else {
                                    seek(by: seekSec)
                                }
                            }
                    )

                // Interactive Region Picker Overlay (Subtitle Erase / Watermark Masking)
                if isPickingEraseRegion || isPickingWatermarkRegion {
                    regionPickerOverlay(size: geo.size)
                }

                // Real-time ASS/SRT/VTT/SMI Subtitle Overlay
                if !activeCueText.isEmpty {
                    VStack {
                        Spacer()
                        Text(activeCueText)
                            .font(.system(size: CGFloat(18.0 * (vm.playerSettings.subtitleSize / 100.0)), weight: vm.playerSettings.vttBold ? .bold : .medium))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.62))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black, radius: 2, x: 1, y: 1)
                            .padding(.bottom, max(28, geo.size.height * CGFloat(vm.playerSettings.subtitleBottomPaddingFraction)))
                            .padding(.horizontal, 24)
                    }
                    .allowsHitTesting(false)
                }

                // AniSkip OP/ED Floating Skip Button
                if vm.playerSettings.showChapterSkipButton, let seg = activeSkipSegment {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Button {
                                seek(to: seg.endTime)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "forward.end.fill")
                                    Text(seg.displayLabel)
                                        .font(.subheadline.bold())
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.purple)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                                .shadow(radius: 6)
                            }
                            .padding(.trailing, 24)
                            .padding(.bottom, 86)
                        }
                    }
                }

                // Loading / Error States
                if isResolvingStream {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.3)
                        Text("\(anime.title) \(currentEpisode.displayNumber)화 스트림 준비 중...")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else if let streamError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text(streamError)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        HStack(spacing: 12) {
                            Button("닫기") { onDismiss() }
                                .buttonStyle(.bordered)
                            Button("다시 시도") {
                                Task { await loadAndPlayEpisode() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                        }
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }

                // Top & Bottom Player HUD Controls
                if showControls && !isPickingEraseRegion && !isPickingWatermarkRegion {
                    controlsOverlay
                }
            }
        }
        .sheet(isPresented: $showSubtitleSheet) {
            subtitlePickerSheet
        }
        .sheet(isPresented: $showFilterSheet) {
            filterAndShaderSheet
        }
        .fileImporter(
            isPresented: $showLocalFileImporter,
            allowedContentTypes: [.item, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                loadLocalSubtitleFile(url: first)
            }
        }
        .task(id: currentEpisode.id) {
            await loadAndPlayEpisode()
        }
        .onDisappear {
            cleanupPlayer()
        }
    }

    // MARK: - Controls Overlay

    private var controlsOverlay: some View {
        VStack {
            // Top Bar
            HStack(spacing: 14) {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.5))
                        .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(anime.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(currentEpisode.displayNumber)화 · \(currentEpisode.title)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer()

                if isTranslatingRealtime {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.75)
                        Text("AI 번역 중")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.purple.opacity(0.85))
                    .clipShape(Capsule())
                }

                Button {
                    showSubtitleSheet = true
                } label: {
                    Label("자막", systemImage: "captions.bubble.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }

                Button {
                    showFilterSheet = true
                } label: {
                    Label("필터/AI", systemImage: "wand.and.stars")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.55))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Spacer()

            // Center Transport Controls
            HStack(spacing: 36) {
                Button {
                    playPreviousEpisode()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                        .foregroundStyle(previousEpisode != nil ? .white : .white.opacity(0.35))
                }
                .disabled(previousEpisode == nil)

                Button {
                    seek(by: -Double(vm.playerSettings.seekButtonSeekSeconds))
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title)
                        .foregroundStyle(.white)
                }

                Button {
                    if isPlaying {
                        player.pause()
                        isPlaying = false
                    } else {
                        player.play()
                        player.rate = vm.playerSettings.playbackSpeed
                        isPlaying = true
                    }
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.white)
                }

                Button {
                    seek(by: Double(vm.playerSettings.seekButtonSeekSeconds))
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title)
                        .foregroundStyle(.white)
                }

                Button {
                    playNextEpisode()
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                        .foregroundStyle(nextEpisode != nil ? .white : .white.opacity(0.35))
                }
                .disabled(nextEpisode == nil)
            }

            Spacer()

            // Bottom Timeline & Speed Bar
            VStack(spacing: 6) {
                Slider(
                    value: Binding(
                        get: { currentTime },
                        set: { seek(to: $0) }
                    ),
                    in: 0...max(duration, 1)
                )
                .tint(.purple)

                HStack {
                    Text("\(formatSeconds(currentTime)) / \(formatSeconds(duration))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white)

                    Spacer()

                    Menu {
                        ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { spd in
                            Button("\(String(format: "%.2gx", spd))") {
                                var s = vm.playerSettings
                                s.playbackSpeed = Float(spd)
                                vm.updatePlayerSettings(s)
                                if isPlaying { player.rate = Float(spd) }
                            }
                        }
                    } label: {
                        Text(String(format: "%.2gx", vm.playerSettings.playbackSpeed))
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.2))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .background(Color.black.opacity(0.32).ignoresSafeArea())
    }

    // MARK: - Region Picker Overlay (Subtitle Erase / Watermark Masking)

    private func regionPickerOverlay(size: CGSize) -> some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if dragStart == nil { dragStart = value.startLocation }
                            dragCurrent = value.location
                        }
                        .onEnded { value in
                            guard let start = dragStart else { return }
                            let end = value.location
                            let minX = min(start.x, end.x) / max(size.width, 1)
                            let minY = min(start.y, end.y) / max(size.height, 1)
                            let w = abs(end.x - start.x) / max(size.width, 1)
                            let h = abs(end.y - start.y) / max(size.height, 1)
                            let newRect = NormalizedRegionRect(x: Float(minX), y: Float(minY), width: Float(w), height: Float(h))
                            var s = vm.playerSettings
                            if isPickingEraseRegion {
                                var list = NormalizedRegionRect.parseList(s.subtitleEraseRegions)
                                list.append(newRect)
                                s.subtitleEraseRegions = NormalizedRegionRect.serializeList(list)
                                s.subtitleEraseEnabled = true
                            } else if isPickingWatermarkRegion {
                                var list = NormalizedRegionRect.parseList(s.watermarkRegions)
                                list.append(newRect)
                                s.watermarkRegions = NormalizedRegionRect.serializeList(list)
                                s.watermarkRemovalEnabled = true
                            }
                            vm.updatePlayerSettings(s)
                            dragStart = nil
                            dragCurrent = nil
                            isPickingEraseRegion = false
                            isPickingWatermarkRegion = false
                            Task { await applyVideoFiltersToCurrentItem() }
                        }
                )

            if let s = dragStart, let c = dragCurrent {
                let rect = CGRect(
                    x: min(s.x, c.x),
                    y: min(s.y, c.y),
                    width: abs(c.x - s.x),
                    height: abs(c.y - s.y)
                )
                Rectangle()
                    .stroke(Color.purple, lineWidth: 2.5)
                    .background(Color.purple.opacity(0.25))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }

            VStack {
                HStack {
                    Text(isPickingEraseRegion ? "지울 하드섭 자막 영역을 드래그하세요" : "지울 워터마크 영역을 드래그하세요")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.75))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    Button("취소") {
                        isPickingEraseRegion = false
                        isPickingWatermarkRegion = false
                        dragStart = nil
                        dragCurrent = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.top, 24)
                Spacer()
            }
        }
    }

    // MARK: - Subtitle Picker & AI Translation Sheet

    private var subtitlePickerSheet: some View {
        NavigationStack {
            List {
                Section("실시간 AI 자막 번역") {
                    Toggle("자막 자동 AI 번역 (\(vm.playerSettings.translationProvider.uppercased()))", isOn: Binding(
                        get: { vm.playerSettings.translationAutoEnabled },
                        set: { enabled in
                            var s = vm.playerSettings
                            s.translationAutoEnabled = enabled
                            vm.updatePlayerSettings(s)
                            if enabled {
                                startRealtimeTranslationPrefetch()
                            } else {
                                translationTask?.cancel()
                                isTranslatingRealtime = false
                            }
                        }
                    ))

                    HStack {
                        Text("싱크 조절")
                        Spacer()
                        Button("-0.5초") {
                            var s = vm.playerSettings
                            s.syncOffsetMs -= 500
                            vm.updatePlayerSettings(s)
                        }
                        .buttonStyle(.bordered)
                        Text(String(format: "%+.1f초", Double(vm.playerSettings.syncOffsetMs) / 1000.0))
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 64)
                        Button("+0.5초") {
                            var s = vm.playerSettings
                            s.syncOffsetMs += 500
                            vm.updatePlayerSettings(s)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Section("로컬 자막 파일 불러오기") {
                    Button {
                        showSubtitleSheet = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showLocalFileImporter = true
                        }
                    } label: {
                        Label("기기에서 .srt / .ass / .smi / .vtt 선택", systemImage: "folder.badge.plus")
                    }
                }

                Section("발견된 온라인 자막 (LinkKF / Jimaku / Anissia)") {
                    if availableSubtitles.isEmpty {
                        Text("검색된 온라인 자막이 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableSubtitles) { opt in
                            Button {
                                Task {
                                    await applySubtitleOption(opt)
                                    showSubtitleSheet = false
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(opt.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text("\(opt.source.uppercased()) · \(opt.format.uppercased())")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedSubtitleOption?.id == opt.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.purple)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("자막 선택 및 AI 번역")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { showSubtitleSheet = false }
                }
            }
        }
    }

    // MARK: - Filter & Shader Sheet (Anime4K / Hard-Sub Erase / Watermark)

    private var filterAndShaderSheet: some View {
        NavigationStack {
            Form {
                Section("Anime4K Metal 셰이더 업스케일링") {
                    Toggle("Anime4K 실시간 업스케일링 활성화", isOn: Binding(
                        get: { vm.playerSettings.aiUpscalingEnabled },
                        set: { val in
                            var s = vm.playerSettings
                            s.aiUpscalingEnabled = val
                            vm.updatePlayerSettings(s)
                            Task { await applyVideoFiltersToCurrentItem() }
                        }
                    ))

                    Picker("Anime4K 프리셋 모드", selection: Binding(
                        get: { vm.playerSettings.aiUpscalingMode },
                        set: { val in
                            var s = vm.playerSettings
                            s.aiUpscalingMode = val
                            vm.updatePlayerSettings(s)
                            Task { await applyVideoFiltersToCurrentItem() }
                        }
                    )) {
                        Text("모드 A (고화질 복원 + 업스케일)").tag("A")
                        Text("모드 B (소프트 복원 + 업스케일)").tag("B")
                        Text("모드 C (노이즈 억제 + 업스케일)").tag("C")
                        Text("모드 A+A (강력 선화 복원)").tag("A+A")
                        Text("모드 B+B (강력 소프트 복원)").tag("B+B")
                        Text("모드 C+A (디노이즈 + 복원)").tag("C+A")
                    }
                }

                Section("하드섭(박힌 자막) 지우기 — SubtitleEraseShaderHq") {
                    Toggle("하드섭 자막 지우기 활성화", isOn: Binding(
                        get: { vm.playerSettings.subtitleEraseEnabled },
                        set: { val in
                            var s = vm.playerSettings
                            s.subtitleEraseEnabled = val
                            vm.updatePlayerSettings(s)
                            Task { await applyVideoFiltersToCurrentItem() }
                        }
                    ))

                    Toggle("디버그 마스크 표시 (감지 영역 미리보기)", isOn: Binding(
                        get: { vm.playerSettings.subtitleEraseDebugMask },
                        set: { val in
                            var s = vm.playerSettings
                            s.subtitleEraseDebugMask = val
                            vm.updatePlayerSettings(s)
                            Task { await applyVideoFiltersToCurrentItem() }
                        }
                    ))

                    Button {
                        showFilterSheet = false
                        isPickingEraseRegion = true
                    } label: {
                        Label("화면에서 하드섭 자막 영역 지정하기", systemImage: "viewfinder.rectangular")
                    }

                    if !vm.playerSettings.subtitleEraseRegions.isEmpty {
                        Button("지정된 하드섭 영역 초기화", role: .destructive) {
                            var s = vm.playerSettings
                            s.subtitleEraseRegions = ""
                            vm.updatePlayerSettings(s)
                            Task { await applyVideoFiltersToCurrentItem() }
                        }
                    }
                }

                Section("워터마크 / 방송사 로고 제거 (Delogo)") {
                    Toggle("워터마크 제거 활성화", isOn: Binding(
                        get: { vm.playerSettings.watermarkRemovalEnabled },
                        set: { val in
                            var s = vm.playerSettings
                            s.watermarkRemovalEnabled = val
                            vm.updatePlayerSettings(s)
                            Task { await applyVideoFiltersToCurrentItem() }
                        }
                    ))

                    Button {
                        showFilterSheet = false
                        isPickingWatermarkRegion = true
                    } label: {
                        Label("화면에서 워터마크 영역 지정하기", systemImage: "crop")
                    }

                    if !vm.playerSettings.watermarkRegions.isEmpty {
                        Button("지정된 워터마크 영역 초기화", role: .destructive) {
                            var s = vm.playerSettings
                            s.watermarkRegions = ""
                            vm.updatePlayerSettings(s)
                            Task { await applyVideoFiltersToCurrentItem() }
                        }
                    }
                }

                Section("앰비언트 조명 & OP/ED 스킵") {
                    Toggle("앰비언트 조명 모드", isOn: Binding(
                        get: { vm.playerSettings.ambientModeEnabled },
                        set: { val in
                            var s = vm.playerSettings
                            s.ambientModeEnabled = val
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
                }
            }
            .navigationTitle("플레이어 필터 & 셰이더")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { showFilterSheet = false }
                }
            }
        }
    }

    // MARK: - Playback & Stream Lifecycle

    private var previousEpisode: Episode? {
        guard let idx = anime.episodes.firstIndex(where: { $0.id == currentEpisode.id }), idx > 0 else { return nil }
        return anime.episodes[idx - 1]
    }

    private var nextEpisode: Episode? {
        guard let idx = anime.episodes.firstIndex(where: { $0.id == currentEpisode.id }), idx + 1 < anime.episodes.count else { return nil }
        return anime.episodes[idx + 1]
    }

    private func playPreviousEpisode() {
        if let prev = previousEpisode {
            currentEpisode = prev
        }
    }

    private func playNextEpisode() {
        if let next = nextEpisode {
            currentEpisode = next
        }
    }

    private func loadAndPlayEpisode() async {
        cleanupPlayer()
        isResolvingStream = true
        streamError = nil
        subtitleCues = []
        activeCueText = ""
        availableSubtitles = []
        skipSegments = []
        activeSkipSegment = nil

        let source = vm.playerSettings.videoSourcePreference
        let resolved = await vm.repository.resolveEpisodeStream(anime: anime, episode: currentEpisode, source: source)

        guard let m3u8 = resolved.m3u8Url, let streamURL = URL(string: m3u8) else {
            isResolvingStream = false
            streamError = "영상 스트림(M3U8)을 추출하지 못했습니다. 다른 소스나 회차를 확인해 주세요."
            return
        }

        // Build AVURLAsset with custom HTTP headers (Referer, Origin, User-Agent)
        let headerMap = FlixCloudHlsProxy.parseHeaders(resolved.headers)
        var assetOptions: [String: Any] = [:]
        if !headerMap.isEmpty {
            assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = headerMap
        }
        let asset = AVURLAsset(url: streamURL, options: assetOptions)
        let item = AVPlayerItem(asset: asset)

        if let comp = await Anime4KShaderManager.buildVideoComposition(for: asset, settings: vm.playerSettings) {
            item.videoComposition = comp
        }

        player.replaceCurrentItem(with: item)
        isResolvingStream = false
        player.play()
        player.rate = vm.playerSettings.playbackSpeed
        isPlaying = true

        attachTimeObserver()

        // Discover Subtitles (Embedded VTT, Jimaku, Anissia)
        Task {
            await discoverAndLoadSubtitles(resolved: resolved)
        }

        // Load AniSkip OP/ED segments
        Task {
            let segs = await OnlineAniSkipService.shared.getSkipSegments(
                title: anime.title,
                episodeNumber: currentEpisode.number,
                anilistId: anime.anilistId,
                malId: anime.malId
            )
            await MainActor.run {
                self.skipSegments = segs
            }
        }
    }

    private func applyVideoFiltersToCurrentItem() async {
        guard let item = player.currentItem else { return }
        item.videoComposition = await Anime4KShaderManager.buildVideoComposition(for: item.asset, settings: vm.playerSettings)
    }

    private func discoverAndLoadSubtitles(resolved: LinkkfApiClient.ResolvedPlayerResult) async {
        var list: [SubtitleDiscoveryService.SubtitleOption] = []
        if let vtt = resolved.subtitleUrl, !vtt.isEmpty {
            list.append(SubtitleDiscoveryService.SubtitleOption(
                source: vm.playerSettings.videoSourcePreference,
                name: "기본 내장 자막 (VTT)",
                creator: vm.playerSettings.videoSourcePreference.uppercased(),
                url: vtt,
                format: "vtt"
            ))
        }
        let jimaku = await SubtitleDiscoveryService.shared.listJimakuSubtitles(anime: anime, episodeNumber: currentEpisode.number)
        list.append(contentsOf: jimaku)

        let anissia = await SubtitleDiscoveryService.shared.listAnissiaSubtitles(animeTitle: anime.title, episodeNumber: currentEpisode.number)
        list.append(contentsOf: anissia)

        self.availableSubtitles = list

        let pref = vm.playerSettings.subtitleSourcePreference
        if let preferred = list.first(where: { $0.source == pref }) ?? list.first {
            await applySubtitleOption(preferred)
        }
    }

    private func applySubtitleOption(_ option: SubtitleDiscoveryService.SubtitleOption) async {
        selectedSubtitleOption = option
        guard let fileURL = await SubtitleDiscoveryService.shared.downloadSubtitle(
            option: option,
            animeId: anime.id,
            episodeKey: currentEpisode.displayNumber
        ),
        let text = SubtitleParser.readSubtitleText(from: fileURL) else { return }

        let parsed = SubtitleParser.parse(content: text, ext: fileURL.pathExtension)
        self.subtitleCues = parsed
        if vm.playerSettings.translationAutoEnabled {
            startRealtimeTranslationPrefetch()
        }
    }

    private func loadLocalSubtitleFile(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard let content = SubtitleParser.readSubtitleText(from: url) else { return }
        let parsed = SubtitleParser.parse(content: content, ext: url.pathExtension)
        subtitleCues = parsed
        if vm.playerSettings.translationAutoEnabled {
            startRealtimeTranslationPrefetch()
        }
    }

    /// Background prefetch translator mirroring Android's `RealtimeSubtitleTranslator.prefetchLoop`.
    private func startRealtimeTranslationPrefetch() {
        translationTask?.cancel()
        guard !subtitleCues.isEmpty else { return }
        isTranslatingRealtime = true

        translationTask = Task {
            let batchSize = max(1, vm.playerSettings.aiBatchSize)
            var index = 0
            while !Task.isCancelled && index < subtitleCues.count {
                let end = min(index + batchSize, subtitleCues.count)
                let slice = Array(subtitleCues[index..<end])
                let untranslatedIndices = slice.enumerated().filter { $0.element.translatedText == nil }.map { index + $0.offset }

                if !untranslatedIndices.isEmpty {
                    let lines = untranslatedIndices.map { SubtitleCue.cleanDisplay(subtitleCues[$0].text) }
                    if let translated = try? await TranslationManager.shared.translateBatchWithFallback(lines: lines, settings: vm.playerSettings) {
                        for (offset, cueIdx) in untranslatedIndices.enumerated() where offset < translated.count && cueIdx < subtitleCues.count {
                            subtitleCues[cueIdx].translatedText = translated[offset]
                        }
                    }
                }
                index = end
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            isTranslatingRealtime = false
        }
    }

    private func attachTimeObserver() {
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            let sec = CMTimeGetSeconds(time)
            guard sec.isFinite else { return }
            Task { @MainActor in
                self.currentTime = sec
                if let dur = self.player.currentItem?.duration, CMTimeGetSeconds(dur).isFinite && CMTimeGetSeconds(dur) > 0 {
                    self.duration = CMTimeGetSeconds(dur)
                    let progress = Float(sec / self.duration)
                    if Int(sec) % 5 == 0 {
                        self.vm.updateWatchProgress(anime: self.anime, episode: self.currentEpisode, progress: progress)
                    }
                    if self.vm.playerSettings.autoPlay && self.duration - sec < 0.8 && self.nextEpisode != nil {
                        self.playNextEpisode()
                    }
                }

                // Active Subtitle Cue Lookup
                let nowMs = Int64(sec * 1000) - self.vm.playerSettings.syncOffsetMs
                if let cue = self.subtitleCues.first(where: { nowMs >= $0.startMs && nowMs <= $0.endMs }) {
                    self.activeCueText = cue.displayText
                } else {
                    self.activeCueText = ""
                }

                // Active AniSkip OP/ED Segment Lookup
                if let seg = self.skipSegments.first(where: { sec >= $0.startTime && sec < $0.endTime - 0.5 }) {
                    self.activeSkipSegment = seg
                    if self.vm.playerSettings.autoSkip {
                        self.seek(to: seg.endTime)
                    }
                } else {
                    self.activeSkipSegment = nil
                }
            }
        }
    }

    private func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, max(duration, seconds)))
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
    }

    private func seek(by delta: Double) {
        seek(to: currentTime + delta)
    }

    private func cleanupPlayer() {
        translationTask?.cancel()
        translationTask = nil
        player.pause()
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }

    private func formatSeconds(_ sec: Double) -> String {
        guard sec.isFinite && sec > 0 else { return "00:00" }
        let total = Int(sec)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
