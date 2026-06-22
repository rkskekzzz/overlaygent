# Persona Writing Agent Implementation Checklist

Source PRD: [persona-writing-agent-prd.md](./persona-writing-agent-prd.md)  
Status markers: `[ ]` not started, `[-]` in progress, `[x]` completed and verified, `[?]` blocked or awaiting decision.

## CoS Operating Rules

- The main thread acts as CoS: owns checklist state, dependency ordering, integration, and verification.
- Implementation work should be delegated to worker subagents whenever practical.
- Read-only investigation can be delegated to explorer subagents.
- Parallel work is allowed only when write scopes are disjoint and no task depends on another unfinished task.
- Worker subagents must not revert unrelated edits and must report changed files and verification commands.
- CoS integrates, resolves conflicts, runs final verification, and updates checklist status.

## Milestone 0: Project Foundation

- [x] M0.1 Create Swift/AppKit project scaffold
  - Owner: worker
  - Dependencies: none
  - Parallel: no, foundation for all code work
  - Scope: `Package.swift` or Xcode project, app entrypoint, app metadata, basic build command
  - Verification: project builds locally

- [x] M0.2 Add baseline app architecture folders
  - Owner: worker
  - Dependencies: M0.1
  - Parallel: no
  - Scope: `App/`, `Dashboard/`, `Accessibility/`, `TextSession/`, `Correction/`, `Overlay/`, `Apply/`, `Storage/`, `Hotkeys/`
  - Verification: build still passes

- [x] M0.3 Add shared domain models
  - Owner: worker
  - Dependencies: M0.1
  - Parallel: yes, after M0.1
  - Scope: `LLMProviderConfig`, `AgentProfile`, `TerminologyRule`, `TextSnapshot`, `ConversationContext`, `AgentRunRequest`, `PrivacyPolicy`
  - Verification: unit tests for Codable round trip

## Milestone 1: Menu Bar Shell and Dashboard

- [x] M1.1 Implement menu bar app shell
  - Owner: worker
  - Dependencies: M0.1, M0.2
  - Parallel: yes with M1.2 if write scopes are separated
  - Scope: `AppDelegate`, `StatusBarController`, menu items, quit action, dashboard open action
  - Verification: app launches and menu is created

- [x] M1.2 Implement dashboard window shell
  - Owner: worker
  - Dependencies: M0.1, M0.2
  - Parallel: yes with M1.1
  - Scope: `DashboardWindowController`, SwiftUI root view, sidebar sections
  - Verification: dashboard opens from menu

- [x] M1.3 Implement provider settings UI and persistence
  - Owner: worker
  - Dependencies: M0.3, M1.2
  - Parallel: yes with M1.4 after M1.2
  - Scope: provider CRUD, base URL/model/temperature/max token/timeout fields
  - Verification: settings persist across launch

- [x] M1.4 Implement agent persona CRUD UI
  - Owner: worker
  - Dependencies: M0.3, M1.2
  - Parallel: yes with M1.3 after M1.2
  - Scope: default agents, create/edit/delete/duplicate, active-in-menu toggle
  - Verification: agent changes persist across launch

- [x] M1.5 Implement active agent menu toggles
  - Owner: worker
  - Dependencies: M1.1, M1.4
  - Parallel: no
  - Scope: `ActiveAgentMenuController`, menu list of agents with toggles, Run Active Agents command
  - Verification: toggles update persisted agent active state

## Milestone 2: Permissions, Hotkeys, and Storage

- [x] M2.1 Implement Accessibility permission coordinator
  - Owner: worker
  - Dependencies: M0.2
  - Parallel: yes with M2.2
  - Scope: `PermissionCoordinator`, AX trust check, settings redirect UX
  - Verification: permission state renders in diagnostics/logs

- [x] M2.2 Implement Keychain-backed API key storage
  - Owner: worker
  - Dependencies: M0.3, M1.3
  - Parallel: yes with M2.1
  - Scope: `KeychainStore`, provider API key save/read/delete, no plaintext logging
  - Verification: keychain save/read test or manual smoke test

- [x] M2.3 Implement global hotkey `Control + Command + O`
  - Owner: worker
  - Dependencies: M1.5
  - Parallel: yes with M2.1/M2.2 after menu shell exists
  - Scope: `HotkeyManager`, trigger run-active-agents flow
  - Verification: hotkey callback fires in app

## Milestone 3: Accessibility Text Session

- [x] M3.1 Implement AX focused element reader
  - Owner: worker
  - Dependencies: M2.1
  - Parallel: no
  - Scope: `AXClient`, `AXElement`, focused UI element, role/subrole/value/selected range
  - Verification: focused native text field can be read

- [x] M3.2 Implement secure field guard
  - Owner: worker
  - Dependencies: M3.1
  - Parallel: yes with M3.3 after M3.1
  - Scope: `AXSecureFieldDetector`, password/secure/private field block
  - Verification: secure-like roles are rejected in unit tests or fixtures

- [x] M3.3 Implement Electron accessibility enabler
  - Owner: worker
  - Dependencies: M3.1
  - Parallel: yes with M3.2
  - Scope: `ElectronAccessibilityEnabler`, `AXManualAccessibility`, bundle allowlist
  - Verification: method is invoked for configured bundle IDs

- [x] M3.4 Implement text snapshot and geometry resolver
  - Owner: worker
  - Dependencies: M3.1, M3.2
  - Parallel: no
  - Scope: `FocusedTextSession`, `TextSnapshot`, selection/caret bounds, content hash
  - Verification: snapshot created for accessible text field

## Milestone 4: Agent Message Assembly

- [x] M4.1 Implement context extraction adapter interfaces
  - Owner: worker
  - Dependencies: M0.3, M3.4
  - Parallel: yes with M4.2
  - Scope: `AppContextAdapter`, `GenericAXContextAdapter`, `ConversationContext`
  - Verification: generic adapter returns nil or safe empty context without crashing

- [x] M4.2 Implement agent memory store
  - Owner: worker
  - Dependencies: M0.3
  - Parallel: yes with M4.1
  - Scope: `AgentMemoryStore`, terminology/tone/writing rules persistence
  - Verification: memory persists and round-trips

- [x] M4.3 Implement agent run request factory
  - Owner: worker
  - Dependencies: M3.4, M4.1, M4.2
  - Parallel: no
  - Scope: `AgentRunRequestFactory`, active agents + snapshot + context + memory + privacy policy
  - Verification: request factory unit tests

- [x] M4.4 Implement agent message factory and context budgeter
  - Owner: worker
  - Dependencies: M4.3
  - Parallel: no
  - Scope: `AgentMessageFactory`, `AgentMessageBundle`, `ContextBudgeter`, provider-neutral messages
  - Verification: stable generated message bundle tests

- [x] M4.5 Implement privacy guard and context redaction pipeline
  - Owner: worker
  - Dependencies: M4.3
  - Parallel: yes with M4.4 if files are disjoint
  - Scope: secure field rejection, disabled app rejection, context opt-in, redaction rules
  - Verification: privacy guard tests

## Milestone 5: LLM Correction Engine

- [x] M5.1 Implement OpenAI-compatible provider client
  - Owner: worker
  - Dependencies: M1.3, M2.2, M4.4
  - Parallel: yes with M5.2 after M4.4
  - Scope: `LLMProvider`, `OpenAICompatibleProvider`, request/response models, timeout
  - Verification: mocked HTTP client tests

- [x] M5.2 Implement correction result parser
  - Owner: worker
  - Dependencies: M4.4
  - Parallel: yes with M5.1
  - Scope: structured JSON parsing, edit ranges, full rewrite fallback
  - Verification: parser fixture tests

- [x] M5.3 Wire correction engine
  - Owner: worker
  - Dependencies: M5.1, M5.2, M4.5
  - Parallel: no
  - Scope: active agent execution, multiple agent results, errors, cancellation
  - Verification: mocked end-to-end correction engine test

## Milestone 6: Overlay and Apply

- [x] M6.1 Implement suggestion overlay shell
  - Owner: worker
  - Dependencies: M3.4
  - Parallel: yes with M6.2
  - Scope: `OverlayController`, `SuggestionPanelController`, floating `NSPanel`
  - Verification: panel can be shown near a test rect

- [x] M6.2 Implement multi-agent result UI
  - Owner: worker
  - Dependencies: M5.2
  - Parallel: yes with M6.1
  - Scope: `AgentResultPagerView`, result divider/tab/pagination, diff display
  - Verification: sample results render in preview or smoke UI

- [x] M6.3 Implement edit appliers
  - Owner: worker
  - Dependencies: M3.4, M5.2
  - Parallel: yes with M6.1/M6.2
  - Scope: `EditApplier`, `AXSelectedTextApplier`, `AXValueApplier`, `ClipboardPasteApplier`
  - Verification: unit tests for selection replacement planning; manual smoke for paste path

- [x] M6.4 Wire hotkey to full preview-and-apply flow
  - Owner: worker
  - Dependencies: M2.3, M5.3, M6.1, M6.2, M6.3
  - Parallel: no
  - Scope: hotkey -> snapshot -> request -> provider -> overlay -> apply
  - Verification: mocked provider smoke test

## Milestone 7: Known App Context Adapters

- [x] M7.1 Implement Slack visible context adapter
  - Owner: worker
  - Dependencies: M4.1, M3.4
  - Parallel: yes with M7.2
  - Scope: Slack bundle detection, message list AX traversal, visible message extraction
  - Verification: adapter fixture tests and manual Slack smoke if available

- [x] M7.2 Implement ChannelTalk visible context adapter
  - Owner: worker
  - Dependencies: M4.1, M3.4
  - Parallel: yes with M7.1
  - Scope: ChannelTalk bundle detection, message list AX traversal, visible message extraction
  - Verification: adapter fixture tests and manual ChannelTalk smoke if available

- [x] M7.3 Implement app compatibility registry and diagnostics
  - Owner: worker
  - Dependencies: M3.3, M4.1, M7.1, M7.2
  - Parallel: no
  - Scope: per-app capability state, failures, redacted diagnostics UI
  - Verification: compatibility state persists and renders

## Milestone 8: Hardening and Release MVP

- [x] M8.1 Add onboarding and privacy copy
  - Owner: worker
  - Dependencies: M1.2, M2.1
  - Parallel: yes with M8.2
  - Scope: first-run permission/privacy screens, current-input-only explanation, context opt-in copy
  - Verification: onboarding can be opened and dismissed

- [x] M8.2 Add focused tests and smoke scripts
  - Owner: worker
  - Dependencies: M5.3, M6.4
  - Parallel: yes with M8.1
  - Scope: build/test commands, fixture tests, mocked provider tests
  - Verification: test suite passes

- [x] M8.3 Final MVP integration pass
  - Owner: CoS
  - Dependencies: all P0/P1 implementation items
  - Parallel: no
  - Scope: verify PRD-critical flow, update docs, record known limitations
  - Verification: clean build and documented smoke result
