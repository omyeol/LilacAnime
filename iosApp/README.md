# 🌸 LilacAnime for iOS (`iosApp`)

Android/Desktop용 **LilacAnime**를 **순수 네이티브 Swift + SwiftUI + Metal + AVKit** 아키텍처로 1:1 포팅한 iOS 버전입니다.

---

## ✨ 포팅된 전체 기능

1. **멀티 스트리밍 소스 및 로컬 프록시 복호화**
   - **LinkKF (`linkani.tv`)**: 홈, 요일별 방영 일정, PV/극장판/16+ 섹션, 장르/연도/분류 태그 필터링, `player_aaaa` 직접 HLS/VTT 추출 (`LinkkfClient.swift`)
   - **Re:ANIME (`reanime.to`)**: HAR API(`/api/v1/search`, `/api/v1/top/anime`, `/api/v1/schedule`) 및 SvelteKit `__data.json` Devalue 레퍼런스 테이블 파서, 헤드리스 `WKWebView` WASM 키 추출 + `NWListener` 로컬 프록시(`FlixCloudHlsProxy.swift`)를 통한 Base64/XOR M3U8 및 PNG/WEBP 세그먼트 래퍼 실시간 복호화
   - **Miruro (`miruro.cx`) & 애니24 (`ohli24.com`)**: AniList GraphQL 연동 및 Inertia `data-page="app"` 파싱 + HLS 스트림 추출 (`MiruroOhli24AndAniSkip.swift`)
2. **온라인 & 로컬 자막 통합 (`SubtitleServices.swift`)**
   - **Jimaku (`jimaku.cc`)**: AniList ID 기반 일본어 자막(`.ass`, `.ssa`, `.srt`) 자동 탐색 및 다운로드
   - **Anissia (`api.anissia.net`)**: 한국어 자막 제작자 색인 조회 및 네이버/티스토리 블로그 첨부파일 자동 추출
   - **로컬 자막 및 다중 인코딩 파서**: UTF-8, EUC-KR(CP949), Shift-JIS, UTF-16 자동 감지 및 `.ass`, `.ssa`, `.srt`, `.smi`, `.vtt` 파싱/렌더링
   - **실시간 싱크 조절**: 플레이어 내 ±0.5초 단위 자막 싱크 오프셋 즉시 반영
3. **클라우드 & 온디바이스 AI 자막 번역 (`CloudTranslators.swift`, `LocalAiAndWhisperService.swift`)**
   - **클라우드 AI 제공자**: **Google Gemini**, **OpenAI** (`/v1/responses` JSON Schema), **Alibaba Qwen** (DashScope International/China), **DeepL API** (`:fx` 무료 및 유료 키) + 쿼터 소진 시 자동 폴백
   - **iOS Keychain 보안 저장**: 모든 API 키를 `SecItemAdd` / `kSecClassGenericPassword` 기반 `SecureApiKeyStore`에 암호화 저장
   - **온디바이스 로컬 AI (`GGUF` / `llama.cpp`)**: HuggingFace 모델 허브(`ggml-org/gemma-4-E2B-it-GGUF` `Q4_0` 등) 검색·다운로드, GGUF 매직 헤더 아키텍처 검사, 문맥 메모리(`Context Cues`) 기반 번역
   - **Whisper 일본어 음성 → SRT 자막 생성**: `whisper.cpp` GGML 모델(`tiny`, `base`, `small`) 다운로드 및 관리
4. **고급 플레이어 & Metal 셰이더 필터 (`LilacShaders.metal`, `Anime4KAndVideoFilter.swift`, `PlayerScreen.swift`)**
   - **Anime4K 실시간 업스케일링**: 프리셋 `A`, `B`, `C`, `A+A`, `B+B`, `C+A` 지원
   - **하드섭(영구 박힌 자막) 지우기 (`SubtitleEraseShaderHq`)**: 획 폭/윤곽선 분류 및 8방향 배경 보간 Metal 커널 + 화면 드래그 영역 지정기
   - **워터마크 제거 (Delogo)**: 화면 드래그 기반 워터마크 영역 마스킹
   - **AniSkip OP/ED 스킵**: AniList ID → MAL ID 자동 변환 및 오프닝/엔딩/요약 구간 건너뛰기(수동 버튼 & 자동 스킵)
   - **오프라인 저장 및 보관함**: 찜한 작품, 시청 기록(이어보기 진행률), 오프라인 회차 관리

---

## 🛠️ 빌드 방법

### 1. GitHub Actions 클라우드 빌드 (Windows / Linux / macOS 공통)
저장소에 푸시하거나 GitHub의 **Actions → Build iOS IPA → Run workflow**를 실행하면 macOS 러너에서 자동으로 서명되지 않은 `LilacAnime-iOS.ipa` 아티팩트를 빌드합니다.
- 다운로드한 `.ipa` 파일은 **AltStore**, **SideStore**, **Sideloadly**, **TrollStore** 등을 통해 iPhone / iPad에 설치할 수 있습니다.

### 2. macOS에서 Xcode로 직접 빌드
```bash
cd iosApp
brew install xcodegen
xcodegen generate
open LilacAnime.xcodeproj
```
Xcode에서 본인 Apple ID(Personal Team)를 Signing Team으로 선택한 뒤 기기 또는 시뮬레이터에서 바로 실행(`Cmd + R`)하세요.
