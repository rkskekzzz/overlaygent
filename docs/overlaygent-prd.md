# Overlaygent PRD

문서 상태: Draft  
작성일: 2026-06-15  
대상 플랫폼: macOS  
작업명: Overlaygent

## 1. 개요

Overlaygent는 macOS에서 메뉴바 아이콘 앱으로 동작하는 OS 레벨 writing assistant이다. 사용자가 Slack, Discord, VS Code, Notion Desktop 등 데스크톱 앱의 입력창에 영어를 작성할 때, 현재 포커스된 입력창의 텍스트를 macOS Accessibility API로 읽고, 사용자가 설정한 LLM provider와 agent persona를 기반으로 문법, 표현, 용어, 톤앤매너를 교정한다.

이 앱은 브라우저 확장 프로그램이 아니며, 화면 캡처/OCR을 기본 방식으로 사용하지 않는다. 기본 동작은 현재 focused text input의 실제 텍스트 상태를 AXUIElement로 읽고, 사용자가 명시적으로 선택한 agent를 실행해 교정 제안을 제공하는 것이다.

핵심 차별점은 단순 문법 교정이 아니라, 사용자가 직접 LLM API key, model, endpoint, system prompt, tone, terminology rules, app별 enable rule을 설정할 수 있는 멀티 페르소나 교정 시스템이라는 점이다.

## 2. 제품 목표

- macOS 메뉴바 앱으로 가볍게 상시 실행된다.
- 사용자가 자기 LLM API key와 model을 설정할 수 있다.
- 사용자가 교정 agent persona를 생성, 수정, 삭제할 수 있다.
- 단축키로 현재 입력창 또는 선택 영역에 대해 활성화된 agent들을 실행할 수 있다.
- Slack, Discord, Notion Desktop, VS Code 등 Electron 기반 앱의 입력창을 우선 지원한다.
- password field, secure input, 비활성화된 앱에서는 텍스트를 읽거나 전송하지 않는다.
- 교정 결과는 입력창 근처 overlay에서 확인하고 사용자가 적용한다.
- 모든 앱에서 100% 동작한다고 가정하지 않고, 앱별 호환성 상태와 fallback을 명확히 제공한다.

## 3. 비목표

- 모든 macOS 앱의 모든 입력창을 완벽히 지원하지 않는다.
- 키보드 입력을 로깅해 텍스트를 재구성하지 않는다.
- 사용자의 전체 화면을 지속 캡처하지 않는다.
- OCR은 기본 경로가 아니며, 명시적 opt-in fallback으로만 제공한다.
- 첫 MVP에서 inline underline, 실시간 Grammarly 스타일 자동 교정, rich text 완전 보존을 목표로 하지 않는다.
- 첫 MVP에서 팀 동기화, cloud profile sync, 조직 관리자 기능은 제외한다.

## 4. 핵심 사용자 시나리오

### 4.1 글 작성 후 수동 교정

1. 사용자가 메뉴바에서 `Natural English` agent를 활성화한다.
2. 사용자가 Slack 입력창에 영어 메시지를 작성한다.
3. 사용자가 `Control + Command + O`를 누른다.
4. 앱이 현재 focused input의 텍스트를 Accessibility API로 읽는다.
5. 앱이 설정된 LLM provider로 현재 텍스트와 활성화된 agent instruction을 전송한다.
6. overlay에 수정 제안과 diff가 표시된다.
7. 사용자가 `Apply`를 누르면 현재 입력창의 텍스트가 교정된다.

### 4.2 여러 agent 동시 실행

1. 사용자가 메뉴바 agent list에서 `Grammar Fixer`, `Coding Terms`, `Tone Polish`를 활성화한다.
2. 사용자가 Discord 또는 Notion에서 문장을 작성한다.
3. 사용자가 `Control + Command + O`를 누른다.
4. 활성화된 agent들이 같은 input snapshot에 대해 실행된다.
5. overlay는 agent별 결과를 divider, tab, 또는 pagination 형태로 구분해 표시한다.
6. 사용자는 원하는 agent 결과만 적용하거나, 하나의 결과를 선택해 전체 적용한다.

### 4.3 코딩 용어 교정

1. 사용자가 VS Code issue/comment input 또는 Slack에 기술 문장을 작성한다.
2. 메뉴바에서 `Coding Terms` agent가 활성화되어 있는지 확인한다.
3. 사용자가 `Control + Command + O`를 누른다.
4. agent는 문법을 과하게 바꾸지 않고, 개발자 영어와 용어 표현만 보정한다.
5. 코드 식별자, command, file path, API name은 보존한다.

### 4.4 앱별 비활성화

1. 사용자가 특정 앱에서는 교정 기능을 끄고 싶어 한다.
2. 메뉴바에서 `Disable for Current App`을 선택한다.
3. 이후 해당 bundle id에서는 focused input을 읽지 않고 overlay도 표시하지 않는다.

## 5. 주요 기능 요구사항

### 5.1 메뉴바 앱

- 앱은 macOS menu bar icon app으로 실행된다.
- Dock icon은 기본적으로 숨긴다.
- 메뉴바 메뉴에는 다음 항목을 제공한다.
  - Run Active Agents
  - Active Agents list with per-agent toggles
  - Enable/Disable for Current App
  - Open Dashboard
  - Permissions
  - Diagnostics
  - Quit

### 5.2 Dashboard

Dashboard는 하나의 설정 창으로 제공한다. AppKit lifecycle 기반 앱에서 SwiftUI view를 `NSHostingView`로 embed하는 방식을 우선 고려한다.

필수 화면:

- General
- LLM Provider
- Agents
- App Rules
- Privacy
- Diagnostics

### 5.3 LLM Provider 설정

사용자는 하나 이상의 LLM provider를 설정할 수 있다. MVP에서는 OpenAI-compatible Chat Completions API를 우선 지원한다.

필드:

- Provider name
- Base URL
- API key
- Default model
- Temperature
- Max tokens
- Timeout seconds
- Test connection

보안 요구사항:

- API key는 Keychain에 저장한다.
- API key는 UI에서 기본적으로 마스킹한다.
- API key는 로그에 남기지 않는다.
- Base URL, model, temperature 등 비밀이 아닌 값은 로컬 settings store에 저장할 수 있다.

### 5.4 Agent Persona 관리

사용자는 agent persona를 생성, 수정, 삭제, 복제할 수 있다.

Agent 필드:

- Name
- Description
- Enabled
- Active in menu
- Provider
- Model override
- Scope
- Tone preset
- Rewrite aggressiveness
- System prompt
- User instruction
- Terminology rules
- App allowlist/blocklist
- Apply mode

Agent 활성화 UX:

- agent는 Dashboard에서 생성, 수정, 삭제한다.
- 메뉴바 상단의 agent list에서 각 agent를 toggle로 활성화하거나 비활성화한다.
- 활성화된 agent들은 `Control + Command + O` 실행 시 동시에 실행된다.
- 여러 agent가 활성화된 경우 overlay는 결과를 agent별로 나누어 보여준다.

기본 agent:

- Grammar Fixer
  - 문법, 철자, 구두점 중심
  - 의미와 톤 변경 최소화
- Natural English
  - 원어민스럽고 자연스러운 표현
  - 의미 유지, 어색한 표현 개선
- Coding Terms
  - 개발자 영어, PR, issue, deploy, API 표현 개선
  - 코드 식별자와 기술 용어 보존
- Tone Polish
  - 더 정중하고 명확한 업무용 톤
  - Slack, Notion, email-style writing에 적합

### 5.5 단축키

MVP 단축키:

- `Control + Command + O`: 현재 focused input 또는 선택 영역에 대해 활성화된 agent들을 실행한다.

agent별 개별 실행 단축키는 MVP에서 제공하지 않는다. agent 활성화/비활성화는 메뉴바 상단 agent list의 toggle로 제어한다. 단축키 충돌이 있을 경우 Dashboard에서 수정할 수 있어야 한다.

### 5.6 Focused Input 읽기

앱은 현재 focused input을 다음 방식으로 읽는다.

1. `AXUIElementCreateSystemWide()`로 system-wide AX element를 만든다.
2. `kAXFocusedUIElementAttribute`로 현재 focused element를 읽는다.
3. role, subrole, editable 여부, secure 여부를 검사한다.
4. `kAXValueAttribute`로 텍스트를 읽는다.
5. `kAXSelectedTextRangeAttribute`로 selection 또는 caret 위치를 읽는다.
6. 가능한 경우 `kAXBoundsForRangeParameterizedAttribute`로 overlay 기준 좌표를 읽는다.

password field 또는 secure text field로 판단되면 즉시 중단한다.

### 5.7 Electron Accessibility 활성화

Electron/Chromium 기반 앱은 accessibility tree가 기본적으로 충분히 노출되지 않을 수 있다.

대상 앱이 Electron 기반으로 판단되면 다음을 시도한다.

```swift
let appAX = AXUIElementCreateApplication(pid)
AXUIElementSetAttributeValue(
    appAX,
    "AXManualAccessibility" as CFString,
    kCFBooleanTrue
)
```

이 처리는 앱별 compatibility registry를 통해 관리한다.

우선 지원 대상:

- Slack
- ChannelTalk
- Discord
- Notion Desktop
- VS Code

앱별로 focused input text read, selected range read, bounds read, direct apply, paste fallback의 성공 여부를 기록한다.

### 5.8 교정 요청

LLM 요청은 전체 시스템 상태가 아니라 최소 텍스트 범위만 포함한다.

요청 범위 우선순위:

1. 사용자가 선택한 텍스트
2. 현재 focused input의 전체 메시지
3. 너무 긴 경우 현재 문단 또는 최대 문자 수 범위

Known app adapter가 있는 앱에서는 사용자의 명시적 설정에 따라 visible conversation context를 함께 포함할 수 있다. 이 context는 현재 화면 또는 accessibility tree에 노출된 최근 메시지로 제한한다.

Context 포함 우선순위:

1. 현재 선택 영역 또는 입력창 draft
2. focused input이 속한 conversation/thread metadata
3. 화면에 보이는 최근 메시지 N개
4. 앱별 adapter가 안정적으로 추출할 수 있는 author, timestamp, message text
5. agent memory에 저장된 사용자 용어, 톤, writing preference

Slack, ChannelTalk처럼 구조를 아는 앱은 `AppContextAdapter`를 통해 메시지 리스트를 해석한다. adapter가 실패하거나 privacy 설정상 context 포함이 꺼져 있으면 current input only로 fallback한다.

LLM 응답은 가능하면 structured JSON으로 받는다.

예시:

```json
{
  "summary": "Made the message more natural and concise.",
  "edits": [
    {
      "rangeStart": 12,
      "rangeEnd": 28,
      "original": "make a deploy",
      "replacement": "deploy it",
      "reason": "More natural engineering phrasing"
    }
  ],
  "fullRewrite": "Can we deploy it after the PR is approved?"
}
```

적용 전에는 현재 input snapshot과 original text range를 다시 비교해 stale edit를 방지한다.

### 5.9 Agent Message Assembly와 디자인 패턴

Agent 실행 요청은 단순 prompt string으로 만들지 않는다. 앱은 `memory`, `context`, `user input`, `agent persona`, `privacy policy`, `output schema`를 조립해 provider-neutral message bundle을 만든 뒤 LLM provider adapter에 전달한다.

권장 실행 흐름:

```text
FocusedTextSession
  -> AppContextAdapter
  -> AgentMemoryStore
  -> AgentRunRequestFactory
  -> AgentMessageFactory
  -> PrivacyGuard
  -> ContextBudgeter
  -> PromptRenderer
  -> LLMProvider
  -> CorrectionResultParser
```

적용할 디자인 패턴:

- Factory Pattern
  - `AgentRunRequestFactory`는 현재 input snapshot, 활성 agent 목록, 앱 context, agent memory를 모아 실행 단위 요청을 만든다.
  - `AgentMessageFactory`는 agent별 system/user/developer message bundle을 생성한다.
  - provider별 API 포맷 차이는 여기서 처리하지 않고 provider adapter로 넘긴다.

- Strategy Pattern
  - `LLMProvider`는 OpenAI-compatible, Anthropic, local model 등 provider별 호출 전략을 바꾼다.
  - `EditApplier`는 AX selected text, AX value, clipboard paste 적용 전략을 바꾼다.
  - `ContextBudgeter`는 agent별로 input/context/memory token budget 배분 전략을 바꾼다.

- Adapter Pattern
  - `SlackContextAdapter`, `ChannelTalkContextAdapter`, `GenericAXContextAdapter`는 앱별 AX tree 구조를 공통 `ConversationContext`로 변환한다.
  - 앱 구조가 바뀌면 adapter만 수정하고 correction pipeline은 유지한다.

- Pipeline 또는 Chain of Responsibility
  - `PrivacyGuard`, `SecureFieldGuard`, `ContextRedactor`, `ContextBudgeter`, `PromptRenderer`를 순서대로 통과시킨다.
  - 각 단계는 요청을 enrich, redact, reject, shrink할 수 있다.

- Repository Pattern
  - `AgentProfileStore`, `LLMProviderStore`, `AgentMemoryStore`는 저장소 구현을 Dashboard와 실행 pipeline에서 분리한다.

Agent message 조립 원칙:

- user input은 항상 가장 높은 우선순위로 보존한다.
- conversation context는 사용자가 opt-in한 경우에만 포함한다.
- agent memory는 사용자 정의 용어집, 톤 선호, 개인 writing rule 중심으로 제한한다.
- 자동으로 대화 로그를 장기 저장하지 않는다.
- LLM 요청 직전 `PrivacyGuard`가 secure field, disabled app, redaction rule을 최종 검증한다.
- prompt는 provider-neutral model로 만든 뒤 provider adapter에서 API별 payload로 변환한다.

예시 message bundle:

```json
{
  "agent": "Coding Terms",
  "app": "Slack",
  "memory": {
    "terminology": ["PR means pull request", "Use deploy, not make deploy"],
    "tone": "concise, friendly, technical"
  },
  "context": {
    "conversation": [
      { "author": "Sam", "text": "Can we ship this after review?" },
      { "author": "Me", "text": "I will make deploy when PR approved." }
    ]
  },
  "input": {
    "scope": "currentInput",
    "text": "I will make deploy when PR approved."
  },
  "outputSchema": "CorrectionResult"
}
```

### 5.10 Overlay

교정 결과는 입력창 근처에 `NSPanel` 또는 transparent `NSWindow`로 표시한다.

요구사항:

- 원래 앱 focus를 가능하면 빼앗지 않는다.
- suggestion list, diff, apply, dismiss를 제공한다.
- 여러 agent 결과는 divider, tab, 또는 pagination으로 구분해 표시한다.
- caret 또는 selection bounds 근처에 표시한다.
- bounds를 얻지 못하면 focused element frame 또는 active window 기준으로 표시한다.
- multi-monitor, Spaces, fullscreen 상태에서 위치 오류를 최소화한다.

MVP에서는 inline underline보다 floating suggestion bubble을 우선 구현한다.

### 5.11 교정 적용

적용 방식은 앱별 capability에 따라 선택한다.

1. AX selected text replacement
   - `kAXSelectedTextRangeAttribute`로 range 설정
   - selected text replacement 시도
   - clipboard를 건드리지 않는 것이 장점
   - Electron editor에서 실패할 수 있음

2. AX value replacement
   - `kAXValueAttribute` 전체 수정
   - native text field에서 단순하고 빠름
   - undo stack, cursor, rich text state가 깨질 수 있음

3. Clipboard paste fallback
   - clipboard 백업
   - 교정문을 clipboard에 넣음
   - paste event 발생
   - clipboard 복원
   - Electron/React editor에서 가장 잘 동작할 수 있음
   - 사용자 신뢰 이슈가 있으므로 opt-in 또는 명확한 설정 필요

MVP 기본값은 preview 후 user-confirmed apply이다. 자동 적용은 제공하지 않는다.

## 6. 개인정보 및 안전 요구사항

- keylogger 방식으로 구현하지 않는다.
- keyboard event monitoring은 text-change 보조 신호로만 사용한다.
- password field, secure input, private browser field로 판단되는 영역은 읽지 않는다.
- 앱별 enable/disable 설정을 제공한다.
- 기본적으로 allowlist 기반 지원을 고려한다.
- 사용자가 선택한 provider로만 텍스트를 전송한다.
- conversation context는 앱별 opt-in이 켜진 경우에만 포함한다.
- context에 포함되는 메시지 수는 사용자가 설정한 최대 개수로 제한한다.
- 자동으로 대화 로그를 장기 저장하지 않는다.
- API key는 로컬 Keychain에 저장한다.
- 로그에는 원문 텍스트, API key, 응답 전문을 남기지 않는다.
- Diagnostics에는 redacted metadata만 표시한다.
- OCR fallback은 opt-in이며, 자동 적용에 사용하지 않는다.

## 7. 권한 요구사항

### 7.1 Accessibility

필수 권한이다.

용도:

- 현재 focused app과 input 감지
- AX tree 탐색
- 텍스트, selection, bounds 읽기
- 지원되는 경우 교정문 적용

UX:

- 첫 실행 시 권한 필요 이유를 설명한다.
- `AXIsProcessTrustedWithOptions`로 상태를 확인한다.
- System Settings > Privacy & Security > Accessibility로 안내한다.

### 7.2 Input Monitoring 또는 CGEvent 보조 신호

필수 권한으로 두지 않는다.

용도:

- hotkey
- 텍스트 변경 debounce 보조
- focused input 변경 감지 보조

키 입력 내용을 저장하거나 재구성하지 않는다.

### 7.3 Screen Recording

MVP 필수 권한이 아니다.

용도:

- OCR fallback
- unsupported input에서 read-only suggestion

사용자가 fallback 기능을 켤 때만 요청한다.

## 8. 실패 케이스와 대응

| 실패 케이스 | 대응 |
| --- | --- |
| AX permission 없음 | onboarding 표시 |
| focused element 없음 | agent 실행 불가 상태 표시 |
| secure/password field | 조용히 중단하거나 보호 상태 표시 |
| AX value 읽기 실패 | 앱 미지원 메시지 |
| selected range 읽기 실패 | 전체 input 교정으로 fallback |
| bounds 읽기 실패 | element frame 또는 window 기준 overlay |
| Electron AX tree 비활성 | `AXManualAccessibility` 설정 후 재시도 |
| VS Code/Monaco editor range 불안정 | manual paste fallback 또는 미지원 |
| Notion rich text mapping 실패 | full rewrite preview 후 paste fallback |
| IME composition 중 | 적용 지연 또는 중단 |
| text snapshot 변경 | stale edit로 판단하고 재실행 요청 |
| clipboard fallback 실패 | clipboard 복원 후 오류 표시 |

## 9. MVP 범위

### 2주 MVP

- Menu bar app
- Dashboard window
- Accessibility permission onboarding
- LLM provider 설정
- API key Keychain 저장
- Agent persona CRUD
- 기본 agent 4개 제공
- Global hotkey: `Control + Command + O`
- Menu bar agent list toggles
- Multi-agent overlay result navigation
- Focused input text read
- Agent message assembly pipeline
- Slack, Discord 중심 수동 교정
- Overlay preview
- Clipboard paste fallback apply
- 앱별 enable/disable

### 4주 MVP

- Notion Desktop 일부 입력 지원
- VS Code comment/search/input box 위주 지원
- AX direct apply 실험적 지원
- 앱별 capability registry
- Slack/ChannelTalk known app context adapter
- opt-in visible conversation context
- Diagnostics panel
- terminology rule editor
- prompt profile import/export
- stale edit detection
- OCR fallback read-only prototype

## 10. 데이터 모델 초안

```swift
struct LLMProviderConfig: Codable, Identifiable {
    var id: UUID
    var name: String
    var baseURL: URL
    var defaultModel: String
    var temperature: Double
    var maxTokens: Int
    var timeoutSeconds: Double
    var keychainServiceName: String
}

struct AgentProfile: Codable, Identifiable {
    var id: UUID
    var name: String
    var description: String
    var isEnabled: Bool
    var isActive: Bool
    var providerID: UUID
    var modelOverride: String?
    var systemPrompt: String
    var instruction: String
    var tone: TonePreset
    var aggressiveness: RewriteAggressiveness
    var scope: CorrectionScope
    var terminologyRules: [TerminologyRule]
    var enabledBundleIDs: [String]
    var disabledBundleIDs: [String]
    var applyMode: ApplyMode
}

struct AgentRunRequest: Codable {
    var input: TextSnapshot
    var activeAgents: [AgentProfile]
    var appContext: ConversationContext?
    var memory: AgentMemory
    var privacyPolicy: PrivacyPolicy
}

struct TextSnapshot: Codable {
    var text: String
    var selectedRange: Range<Int>?
    var sourceBundleID: String
    var sourceElementRole: String?
    var contentHash: String
}

struct ConversationContext: Codable {
    var appBundleID: String
    var conversationTitle: String?
    var visibleMessages: [ConversationMessage]
}

struct ConversationMessage: Codable, Identifiable {
    var id: UUID
    var author: String?
    var timestamp: Date?
    var text: String
}

struct AgentMemory: Codable {
    var terminologyRules: [TerminologyRule]
    var tonePreferences: [String]
    var writingRules: [String]
}

struct PrivacyPolicy: Codable {
    var includeConversationContext: Bool
    var maxVisibleMessages: Int
    var allowClipboardFallback: Bool
    var redactionRules: [String]
}

struct TerminologyRule: Codable, Identifiable {
    var id: UUID
    var match: String
    var replacement: String
    var note: String?
    var isCaseSensitive: Bool
}

enum CorrectionScope: String, Codable {
    case selectedText
    case currentInput
    case currentParagraph
}

enum ApplyMode: String, Codable {
    case askEveryTime
    case axSelectedText
    case axValue
    case clipboardPaste
}
```

## 11. Swift 코드 구조

```text
App/
  ActiveAgentRunTaskController.swift
  AppEnvironment.swift
  AppDelegate.swift
  RunActiveAgentsCoordinator.swift
  StatusBarController.swift

Dashboard/
  AgentEditorView.swift
  AgentListView.swift
  DashboardDependencies.swift
  DashboardRootView.swift
  DashboardSection.swift
  DashboardWindowController.swift
  DiagnosticsView.swift
  OnboardingView.swift
  PrivacyView.swift
  ProviderSettingsView.swift

Accessibility/
  AXClient.swift
  AXElement.swift
  AXGeometryResolver.swift
  AXSecureFieldDetector.swift
  ElectronAccessibilityEnabler.swift
  FocusedApplicationAccessibilityPreparer.swift

TextSession/
  AccessibilityPreparingInputCapture.swift
  FocusedTextSession.swift

ContextExtraction/
  AppContextAdapter.swift
  ChannelTalkContextAdapter.swift
  SlackContextAdapter.swift

AgentMessageAssembly/
  AgentMessageBundle.swift
  AgentMessageFactory.swift
  AgentRunRequestFactory.swift
  ContextBudgeter.swift

AgentOrchestration/
  AgentOrchestrator.swift

Memory/
  AgentMemoryStore.swift

Correction/
  AgentSuggestion.swift
  CorrectionEngine.swift
  CorrectionResultParser.swift
  LLMProvider.swift
  LLMResponseCaching.swift
  LLMResponseCacheKeyFactory.swift
  OpenAICompatibleProvider.swift
  PrivacyGuard.swift

Logging/
  SafeLogger.swift

Shared/
  ContextRedactor.swift

Domain/
  BundleIdentifier.swift
  SharedDomainModels.swift

Overlay/
  AgentResultPagerView.swift
  OverlayController.swift
  SuggestionPanelController.swift

Apply/
  AXSelectedTextApplier.swift
  AXValueApplier.swift
  ClipboardPasteApplier.swift
  EditApplier.swift
  SuggestionApplyCoordinator.swift

Storage/
  AgentProfileStore.swift
  ApplicationSupportPaths.swift
  DefaultSeedConfiguration.swift
  JSONFileStore.swift
  KeychainStore.swift
  LLMProviderAPIKeyStoring.swift
  LLMProviderStore.swift
  LLMResponseCache.swift
  OrchestratorSettingsStore.swift
  SeededLLMProviderConfigLoader.swift

Hotkeys/
  CarbonHotkeyRegistrar.swift
  HotkeyConfig.swift
  HotkeyManager.swift

Permissions/
  AccessibilityPermission.swift
  PermissionCoordinator.swift

Compatibility/
  AppCompatibilityRegistry.swift
  KnownAppCatalog.swift
```

## 12. LLM Prompt 방향

각 agent는 다음 요소를 조합해 prompt를 생성한다.

- Global system policy
- Agent system prompt
- Agent instruction
- Tone preset
- Aggressiveness
- Terminology rules
- App context
- Text scope
- Output JSON schema

공통 원칙:

- 의미를 바꾸지 않는다.
- 사용자가 작성한 code, identifiers, file paths, commands는 보존한다.
- 교정 범위 밖의 텍스트를 생성하지 않는다.
- 응답은 JSON schema를 따른다.
- 불확실하면 full rewrite보다 작은 edit를 선호한다.

## 13. 성공 지표

MVP 성공 기준:

- 사용자가 Slack 또는 Discord 입력창에서 `Control + Command + O`로 활성화된 agent들을 실행할 수 있다.
- 교정 결과가 3초 이내에 overlay로 표시된다.
- 사용자가 preview 후 적용할 수 있다.
- API key와 agent persona를 dashboard에서 수정할 수 있다.
- secure field에서는 텍스트를 읽지 않는다.
- 앱별 enable/disable이 동작한다.

정성 지표:

- 사용자가 Grammarly처럼 이해할 수 있지만, 더 커스텀 가능하다고 느낀다.
- coding terminology와 tone persona가 일반 문법 교정보다 유의미한 차별점을 만든다.
- 지원되지 않는 앱에서도 실패 이유가 명확하다.

## 14. 주요 리스크

- Electron 앱별 AX 호환성이 일정하지 않다.
- rich text editor에서 plain text range와 실제 editor state가 어긋날 수 있다.
- overlay가 focused app의 입력 흐름을 방해할 수 있다.
- clipboard fallback은 UX 신뢰 리스크가 있다.
- macOS 권한 요청 과정이 사용자 이탈을 만들 수 있다.
- LLM provider별 응답 format 차이와 latency가 있다.
- 사용자 원문 텍스트 처리에 대한 privacy expectation을 명확히 충족해야 한다.

## 15. 우선순위

P0:

- Accessibility permission
- focused input text read
- LLM provider setup
- API key Keychain storage
- agent CRUD
- hotkey run active agents
- overlay preview
- user-confirmed apply
- secure field block

P1:

- app compatibility registry
- terminology rule editor
- multi-agent result pagination
- per-app enable/disable
- diagnostics
- stale edit detection

P2:

- automatic armed mode
- OCR fallback
- inline underline
- team profile sharing
- local model provider
- cloud sync
