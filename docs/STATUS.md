# Project status

Last updated: 2026-08-11

This file uses five independent evidence categories. A feature can be implemented without being compiled for every target, and it can compile without being run on a simulator or physical device.

| Category | Meaning in this repository |
| --- | --- |
| **Implemented** | Source exists and has been reviewed in the current worktree. |
| **Compiled** | A recorded build compiled the stated target/configuration. The platform qualifier matters. |
| **Unit tested** | Deterministic automated tests exercised the feature without live services/hardware. |
| **Simulator tested** | The app/flow was actually launched and exercised in iOS Simulator, not merely compiled for the simulator SDK. |
| **Hardware tested** | The flow was exercised on a named physical iPhone/Rokid setup with recorded evidence. |

## Evidence snapshot

- `swift test --parallel`: **72 passed, 0 failed** on 2026-08-11 (53 XCTest + 19 Swift Testing).
- That run compiled `RokidLyricsCore` and `RokidLyricsServices` for the macOS package test host.
- A generated-project iOS Simulator build was attempted, but `xcodebuild` exited 70 before the Xcode target build because the local installation is missing the required system `CoreSimulator.framework` used by `IDESimulatorFoundation`.
- The public/mock [GitHub Actions run 31483973369](https://github.com/Klayertan/rokid-lyrics-ios/actions/runs/31483973369) passed formatting, all 72 package tests, XcodeGen generation, and an unsigned generic iOS Simulator build with Xcode 16.4. It did not launch the app.
- After the conditional CXR-L path was wired into `AppModel` and the SwiftUI URL callback, the complete main-app Swift source set passed strict Swift 6 arm64 iPhoneOS 17 compilation with whole-module optimization and emitted a 2.1 MB object against the inspected real `RGCxrClient` interface. This was **compile-to-object evidence only**, not a final link/app bundle: the check used a temporary empty `RGCoreKit` module solely to satisfy the client framework interface import.
- Strict Swift 6 whole-module compilation also emitted a 1.9 MB arm64 iOS 17 Simulator object for the public/mock app and a 111 KB object for the Share Extension. Neither was linked into an Xcode-built bundle or launched.
- No iOS Simulator launch has been recorded.
- No signed iPhone run has been recorded.
- No microphone/Shazam live recognition has been recorded.
- No live LRCLIB request has been recorded; provider tests use an injected stub.
- No physical Rokid device test has been recorded.
- The proprietary SDK binary is not committed.
- Public/mock GitHub Actions is passing for the recorded run above; it contains no proprietary Rokid framework or credential.

## Feature matrix

| Feature | Implemented | Compiled | Unit tested | Simulator tested | Hardware tested |
| --- | --- | --- | --- | --- | --- |
| Domain models and service protocols | Yes | Yes — macOS Swift package | Yes | No | No |
| LRC parser, metadata/offset handling, Unicode, duplicate sorting | Yes | Yes — macOS Swift package | Yes | No | No |
| Lyric timeline, seek/offset/progress | Yes | Yes — macOS Swift package | Yes | No | No |
| Monotonic playback clock and synchronization state machine | Yes | Yes — macOS Swift package | Yes | No | No |
| Per-track correction stores | Yes | Yes — macOS Swift package | In-memory store and engine persistence behavior | No | No |
| Conservative multilingual lyrics normalization/scoring | Yes | Yes — macOS Swift package | Yes | No | No |
| LRCLIB `/api/search` adapter | Yes | Yes — macOS Swift package | Yes — stubbed HTTP | No | No live service test |
| HTTP timeout/retry/cancellation layer | Yes | Yes — macOS Swift package | Yes for transient retry, long `Retry-After`, provider failure, and cancellation; no direct timeout test | No | No |
| Memory/disk lyrics caches | Yes | Yes — macOS Swift package | Memory cache hit only | No | No |
| ShazamKit signature identification adapter | Yes | Yes — macOS package plus device and simulator-target app objects | No direct adapter test | No | No live recognition |
| Phone microphone `AVAudioEngine` capture | Yes | Yes — macOS package plus device and simulator-target app objects | No | No | No iPhone/audio-route test |
| SwiftUI Home, Now Playing, Connection, Search, Settings, Diagnostics | Yes | Yes — arm64 iPhoneOS real-SDK object and arm64 iOS Simulator mock object; neither linked/bundled | No UI tests | No | No |
| Phone-side glasses simulator view | Yes | Yes — included in both main-app objects; not launched | Domain display model is tested; view is not | No | No |
| Mock Rokid transport, coalescing, failure states | Yes | Yes — macOS Swift package | Yes | No | No |
| Share parser and App Group inbox | Yes | Yes — macOS Swift package | Parser yes; inbox no | No | No |
| iOS Share Extension UI and standard text/URL intake | Yes | Yes — 111 KB arm64 iOS Simulator object; not linked/bundled | Parser only | No | No YouTube Music share test |
| SDK-neutral CXR-L CustomView JSON payload encoder | Yes | Yes — macOS Swift package | Yes — shape, Unicode escaping, line visibility, font scale, vertical gravity mapping, and progress coalescing | No | No |
| Conditional real CXR-L transport/coordinator and app wiring | Yes — behind `ROKID_SDK_AVAILABLE && canImport(RGCxrClient)` | Compiled into the 2.1 MB arm64 iPhoneOS object against actual client APIs; not linked/bundled | JSON encoder only; SDK coordinator not unit tested | Not applicable to current device-only SDK binary | No |
| Conditional Rokid glasses PCM capture and app wiring | Yes — behind the same SDK guard | Compiled into the same object against actual client APIs; not linked/bundled | No | Not applicable to current device-only SDK binary | No |
| Translation and transliteration | Placeholder settings only | Settings compile in source package/app pending | No | No | No |
| Advanced `AudioAlignmentService` | Protocol only | Yes — protocol in macOS package | No implementation | No | No |
| Public/mock GitHub Actions workflow | Yes | Yes — run 31483973369 passed the generic mock build | 72/72 in the hosted run | No app launch | No |

## Rokid SDK status

The official public [CocoaPods specification](https://cdn.cocoapods.org/Specs/b/d/c/RGCxrClient/1.0.4/RGCxrClient.podspec.json) identifies `RGCxrClient` 1.0.4, depends on `RGCoreKit` 0.0.2, and points to an artifact whose filename is revision 1.0.4.2. Rokid's official [CXR-L iOS sample archive](https://rokid-ota.oss-cn-hangzhou.aliyuncs.com/toB/Document/CXR-L/v1.0.4/iOS/ios_cxr_l_sample.zip) pins `RGCxrClient` 1.0.4.2. The inspected framework reports bundle version 1.0.4 and contains an arm64 iPhoneOS slice rather than a simulator slice; see the SDK notes for the exact local interface/Info.plist evidence and version nuance.

Those facts do **not** mean the application currently works with glasses. At this snapshot:

- the SDK binary is not redistributed in the repository;
- the SDK-neutral payload encoder exists;
- conditional real transport/coordinator, glasses PCM, mode selection, and URL callback are wired and compiled to an object against the actual client APIs, but no final SDK-linked app bundle has been produced;
- no device discovery/availability, authorization, connection, display, reconnection, microphone stream, background, Unicode rendering, payload-limit, or update-rate behavior has been hardware tested.

See [`ROKID_SDK_NOTES.md`](ROKID_SDK_NOTES.md) for the exact official URLs, inspected framework/interface paths, installation/legal constraints, and any status newer than this snapshot.

## Implemented application behavior

- Protocol-isolated audio capture, identification, lyric provider, future alignment, correction persistence, and display transport boundaries.
- Public ShazamKit signature matching with optional confidence rather than fabricated values.
- Runtime LRCLIB search with status validation, decoding errors, cancellation, bounded retry behavior, and injected caching.
- Conservative title/artist/version normalization for accented Latin and CJK metadata.
- Full LRC parsing and immutable binary-search timeline.
- Monotonic clock; pause/resume, seek, resync, previous/next line, and manual offset controls.
- Per-track manual correction persistence.
- SDK-neutral previous/current/next display model and duplicate-coalescing mock transport.
- Phone-side mock display presentation.
- SwiftUI screens for Home, Now Playing, Connection, Search, Settings, and Developer Diagnostics.
- Standard iOS Share Extension intake, explicit confirmation, and App Group handoff.
- Bounded local lyrics cache and no committed fetched lyrics.
- Conditional real CXR-L coordinator/display/PCM adapters and AppModel/URL-callback wiring; the default setting remains Mock Mode with the phone microphone.

## Not yet proven

The following claims must not appear without newer evidence:

- “Works with Rokid Glasses.”
- “Rokid integration complete.”
- “YouTube Music keeps playing during recognition.”
- “YouTube Music share always supplies title and artist.”
- “Recognition works while the app is backgrounded.”
- “Japanese, Chinese, and Korean glyphs render on the glasses.”
- “Rokid glasses microphone audio is available to this app.”
- “The app is App Store ready.”

## Known limitations and intentional remainders

- YouTube Music playback state, queue, elapsed time, pause, seek, and track-change events are not accessible through the supported architecture.
- Microphone/audio-session coexistence with YouTube Music is documented in intent but not experimentally verified.
- The app declares no audio background mode and does not promise continuous background execution.
- The source player's digital audio stream is not captured; recognition depends on the selected microphone/input hearing music.
- The current Settings toggle switches transport and capture together: Mock Mode uses mock display + phone microphone, while SDK mode uses real display + glasses PCM. There is no user-facing hybrid real-display/phone-microphone selector, although the injected composition can support alternate pairings.
- The verified CustomView encoder maps vertical preference to root gravity in the open payload. The conditional adapter detects a gravity change and uses the verified close/open lifecycle because the official sample does not demonstrate updating root gravity in place; hardware behavior remains untested.
- Manual/search workflows have no trustworthy source-player position and require user synchronization.
- Actual YouTube Music Share Extension payloads are unverified; URL-only input remains incomplete by design.
- LRCLIB may return no lyrics, incorrect metadata, ambiguous versions, plain-only lyrics, or instrumentals.
- Automatic candidate selection filters instrumental and missing/empty synchronized records before scoring; manual selection still reports an explicit error for unusable records.
- Cache clearing and per-track correction deletion are not exposed in the current UI.
- Audio-route interruption/recovery and long-running suspension behavior need device work.
- Translation/transliteration are visibly labeled placeholders.
- `AudioAlignmentService` is an extension point only.
- Real SDK authorization, lifecycle, display constraints, background behavior, Unicode support, and licensing/distribution remain governed by verified SDK notes and hardware tests.

## Test and hardware next gates

1. Record a clean generated Xcode mock build for iOS Simulator.
2. Launch and exercise every SwiftUI screen and the mock display in Simulator.
3. Build/install the mock configuration on a signed iPhone.
4. Verify microphone permission, route, Stop/cancellation, and YouTube Music coexistence on device.
5. Verify live ShazamKit identification and live LRCLIB metadata lookup without saving lyric content as evidence.
6. Capture actual standard share items from the current YouTube Music build and keep confirmation conservative.
7. Produce a final SDK-linked, signed device app bundle from the object-compiling sources without committing binaries or credentials.
8. Execute stages A–K in [`HARDWARE_TEST_PLAN.md`](HARDWARE_TEST_PLAN.md).
9. Update this file only from recorded results, keeping object compilation, linking, simulator, and hardware labels separate.
