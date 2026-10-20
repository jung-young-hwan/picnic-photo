# 피크닉(Picnic) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 아이폰 사진을 한국어로 검색하고 불필요한 사진을 골라 지우는 SwiftUI 앱을 만들고, Windows에서 GitHub Actions로 빌드해 사이드로드한다.

**Architecture:** 모듈별 폴더(Store/Analysis/Lexicon/Search/Cleanup/Library/Indexer/Places/UI). 순수 로직(Analysis 계산, Search 해석, Cleanup 그룹핑, Store)은 PhotoKit 없이 단위 테스트한다. PhotoKit·Vision 연결부는 얇게 유지한다.

**Tech Stack:** Swift 5.10+, SwiftUI, iOS 18, GRDB.swift 7 (SPM), Vision, Accelerate, Photos, CoreLocation, XcodeGen, GitHub Actions (macos-15).

## Global Constraints

- 최소 iOS 18.0, iPhone 전용, 세로 화면.
- 외부 의존성은 GRDB.swift 하나.
- 번들 ID `com.jungyounghwan.picnic`, 표시 이름 "피크닉".
- 사진은 기기 밖으로 보내지 않는다 (CLGeocoder 좌표 조회만 예외).
- 썸네일을 직접 저장하지 않는다. 앱 저장 용량 목표: 5만 장 기준 60MB 이하.
- 삭제는 항상 사용자가 선택 + 시스템 확인 창 (`PHAssetChangeRequest.deleteAssets`).
- 비공개 API 금지, `PrivacyInfo.xcprivacy` 포함.
- UI 문구는 친근한 해요체 한국어.
- 색 토큰: cream #FBF7F2, rose #E58F9E, sage #A8C3A0, lavender #BDB2E0, butter #F6D98B, ink #3B3335, 다크 배경 #1E1A1B.

## 빌드·검증 루프

Windows에는 Swift 툴체인이 없으므로 모든 컴파일·테스트는 GitHub Actions에서 한다.
- 각 작업 후 `git push` → `gh run watch` 로 결과 확인 → 실패 시 로그(`gh run view --log-failed`)를 보고 수정.
- 워크플로는 `xcodegen generate` → `xcodebuild test`(iPhone 16 시뮬레이터) → `xcodebuild archive`(서명 없음) → `Payload/Picnic.app` 을 zip 한 `Picnic.ipa` 업로드.

## 파일 구조

```
project.yml
Picnic/
  App/PicnicApp.swift, RootView.swift, AppModel.swift
  Store/Database.swift, Records.swift, AssetStore.swift
  Analysis/ImageMath.swift (sharpness, dHash — CGImage 입력 순수 계산)
  Analysis/VisionAnalyzer.swift (Vision 요청 묶음)
  Lexicon/Lexicon.swift, Resources/lexicon_ko.json
  Search/QueryParser.swift, SearchService.swift
  Cleanup/CleanupService.swift, SimilarGrouper.swift
  Library/PhotoLibrary.swift (PhotoKit 래퍼), ThumbnailView.swift
  Indexer/Indexer.swift
  Places/PlaceResolver.swift
  UI/Theme.swift, Components/*.swift, Search/*.swift, Cleanup/*.swift, Settings/*.swift
  UI/Selection/SelectionModel.swift, SelectableGrid.swift
  Resources/Assets.xcassets, PrivacyInfo.xcprivacy, Info.plist 키는 project.yml 에서 생성
PicnicTests/
  StoreTests.swift, ImageMathTests.swift, LexiconTests.swift,
  QueryParserTests.swift, SearchServiceTests.swift, SimilarGrouperTests.swift,
  CleanupServiceTests.swift, SelectionModelTests.swift
.github/workflows/build.yml
docs/INSTALL.md
```

## 작업

### Task 1: 프로젝트 골격 + CI
- Files: `project.yml`, `Picnic/App/PicnicApp.swift`, `PicnicTests/SmokeTests.swift`, `.github/workflows/build.yml`, `.gitignore`
- 산출물: GitHub 공개 저장소 `picnic-photo`, 녹색 CI, 다운로드 가능한 `Picnic.ipa` 아티팩트.
- 테스트: `XCTAssertTrue(true)` 수준의 스모크 테스트로 파이프라인 확인.

### Task 2: Store (GRDB)
- Files: `Store/Database.swift`, `Store/Records.swift`, `Store/AssetStore.swift`, `PicnicTests/StoreTests.swift`
- Produces:
  - `struct AssetRecord` (id, mediaType, createdAt, lat, lon, placeID, isScreenshot, fileSize, sharpness, aesthetic, isUtility, dhash, analyzedVersion, pixelWidth, pixelHeight, duration)
  - `struct AnalysisResult` (labels: [(String, Float)], ocrText: String?, sharpness, aesthetic, isUtility, dhash)
  - `final class AssetStore` — `init(dbQueue:)`, `static func inMemory()`, `upsertMetadata([AssetMetadata])`, `removeAssets(notIn:)`, `saveAnalysis(id:result:version:)`, `pendingAnalysisIDs(version:limit:)`, `counts()`, `place(gridKey:)`, `savePlace(...)`, `assetsNeedingPlace(limit:)`, `excluded`, `exclude(ids:)`
- 테스트: 메타데이터 upsert 후 재-upsert 시 분석 결과 유지, 분석 저장 후 pending 목록에서 빠짐, 사라진 에셋 삭제 시 label/ocr 연쇄 삭제.

### Task 3: ImageMath (선명도·dHash)
- Files: `Analysis/ImageMath.swift`, `PicnicTests/ImageMathTests.swift`
- Produces: `ImageMath.sharpness(of: CGImage) -> Double`, `ImageMath.dHash(of: CGImage) -> UInt64`, `ImageMath.hamming(_:_:) -> Int`
- 테스트: 체커보드(선명) > 같은 이미지를 흐린 버전 sharpness, 같은 이미지 dHash 거리 0, 반전 이미지 거리 큼.

### Task 4: Lexicon
- Files: `Lexicon/Lexicon.swift`, `Resources/lexicon_ko.json`, `PicnicTests/LexiconTests.swift`
- Produces: `Lexicon.shared.labels(for: String) -> Set<String>`, `Lexicon.shared.korean(for label: String) -> String?`
- 테스트: "강아지"→dog 포함, "개"→dog, 영어 라벨 그대로 입력 시 자기 자신, 모든 항목 비어있지 않음.

### Task 5: 검색 (QueryParser + SearchService)
- Files: `Search/QueryParser.swift`, `Search/SearchService.swift`, 테스트 2개
- Produces: `QueryParser.parse(_ text: String, now: Date) -> [QueryTerm]`; `enum QueryTerm { case date(DateInterval), flag(Flag), text(String) }`; `SearchService.search(_ text: String) throws -> [SearchHit]` (`SearchHit` = id + reasons)
- 테스트: "2023년 8월"→해당 월 구간, "작년"→작년 구간, "스크린샷"→flag, "제주 바다"→ text 두 개 AND; 메모리 DB에서 라벨/OCR/지명 매칭.

### Task 6: 정리 (SimilarGrouper + CleanupService)
- Files: `Cleanup/SimilarGrouper.swift`, `Cleanup/CleanupService.swift`, 테스트 2개
- Produces: `SimilarGrouper.group(_ items: [GroupItem], refine: (String, String) -> Float?) -> [[String]]`; `CleanupService.candidates(_ category: CleanupCategory) throws -> CleanupResult` (items + defaultSelected + totalBytes, similar 는 groups 포함)
- 테스트: 3분 넘게 떨어진 사진은 묶이지 않음, 해밍 ≤3 중복, 추천 사진 = 선명도×미적 최대, 흐림 하위 5% 기준, 제외 목록 반영.

### Task 7: 선택 모델 (전체 선택·드래그 범위)
- Files: `UI/Selection/SelectionModel.swift`, `PicnicTests/SelectionModelTests.swift`
- Produces: `@Observable final class SelectionModel` — `selected: Set<String>`, `selectAll(_:)`, `deselectAll()`, `toggle(_:)`, `beginDrag(at index:, ids:)`, `updateDrag(to index:)`, `endDrag()`
- 테스트: 비선택 칸에서 시작→범위 선택, 선택 칸에서 시작→범위 해제, 범위 축소 시 원래 상태 복원.

### Task 8: PhotoKit·Vision·인덱서·지명
- Files: `Library/PhotoLibrary.swift`, `Analysis/VisionAnalyzer.swift`, `Indexer/Indexer.swift`, `Places/PlaceResolver.swift`
- 시뮬레이터 단위 테스트 대상 아님 (실기기 확인). 컴파일 통과가 기준.

### Task 9: UI (테마, 탭, 그리드, 드래그 선택 제스처)
- Files: `UI/**`, `App/RootView.swift`, `App/AppModel.swift`
- 검색 탭, 정리 홈 + 카테고리 상세, 설정 탭, 사진 크게 보기, 진행 배너.

### Task 10: 마무리
- 앱 아이콘, `PrivacyInfo.xcprivacy`, `docs/INSTALL.md` (AltStore/Sideloadly 설치 안내), 최종 CI 녹색, 실기기 확인 체크리스트.
