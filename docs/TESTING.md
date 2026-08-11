# Testing

The default automated suite is deterministic, uses fictional lyric text, performs no live network request, and requires neither Rokid hardware nor a proprietary SDK.

## Verified automated result

On 2026-08-12, this command completed successfully in the working repository:

```sh
swift test --parallel
```

Result:

| Runner | Tests | Passed | Failed |
| --- | ---: | ---: | ---: |
| XCTest (`RokidLyricsCoreTests`) | 53 | 53 | 0 |
| Swift Testing (`RokidLyricsServicesTests`) | 27 | 27 | 0 |
| **Total** | **80** | **80** | **0** |

Local validation environment:

- macOS 27.0 (`26A5378j`);
- Xcode 26.6 (`17F113`);
- Apple Swift 6.3.3;
- XcodeGen 2.46.0;
- Swift package deployment platforms: iOS 17 and macOS 14.

This is package compilation and unit-test evidence. Separate checks cover iOS source compilation and linking. None of these results is evidence of a launched iOS Simulator app, signed physical-iPhone install, live Shazam/LRCLIB result, or Rokid hardware behavior. Those categories are tracked separately in [`STATUS.md`](STATUS.md).

The complete public/mock app and Share Extension source sets also passed strict Swift 6 arm64 iPhoneOS 17 typechecking. The Share Extension then completed an unsigned `Mock-Debug` target build for arm64 iPhoneOS. A separate app-target command with `Assets.xcassets` excluded only on the command line linked an unsigned `Mock-Debug` arm64 iOS 17 `.app` and embedded the Share Extension; `/tmp/rokid-mock-app-final-xcodebuild.log` ends `BUILD SUCCEEDED`. This proves the current mock app/extension source composition and link, but the bundle was not asset-complete, signed, installed, or launched.

A normal generated main-app scheme build still cannot complete on this machine: Xcode reports the iOS 26.5 platform/runtime unavailable, and `actool` reports that no runtime is available. This is an environment/toolchain failure, not a passing normal main-app build or Simulator result. Both generated iOS targets force `TARGETED_DEVICE_FAMILY=1`.

Separately, CocoaPods resolved and built the genuine graph `RGCxrClient` 1.0.4 → `RGCoreKit` 0.0.2 → `CocoaLumberjack/Swift` 3.9.1. A target-mode arm64 iOS 17 build compiled the current app sources, linked the executable against all three real frameworks, and embedded them. That validation excluded `Assets.xcassets` on the command line solely to bypass the same broken local `actool` runtime. The ordinary `Rokid Lyrics Hardware` workspace build still could not start because the generic iOS destination was ineligible. The target-mode bundle was not asset-complete, signed, installed, launched, authorized, or connected to hardware. Report it as **linked against and embedded the genuine SDK dependency chain**, never as a normal workspace/device build or completed integration. Exact commands and artifact evidence are in [`ROKID_SDK_NOTES.md`](ROKID_SDK_NOTES.md).

## Quick commands

From the repository root:

```sh
swift test --parallel
```

Generate the Xcode project and build the public/mock configuration for a generic iOS Simulator:

```sh
xcodegen generate
xcodebuild \
  -project RokidLyrics.xcodeproj \
  -scheme 'Rokid Lyrics Mock' \
  -configuration Mock-Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The generated `.xcodeproj` is an output of `project.yml`; regenerate it after project configuration changes. Do not hand-edit generated project settings.

If `xcodebuild` reports that the requested iOS platform is not installed, that no destination is eligible, or that `actool` has no runtime, repair/complete the Xcode platform installation using Apple's supported component/first-launch process before retrying. Do not mark the app built or Simulator-tested from that failed attempt, and do not use the asset-exclusion link probe as a normal-build substitute.

To see individual package tests:

```sh
swift test list
```

To run one XCTest class or one service suite while iterating:

```sh
swift test --filter LRCParserTests
swift test --filter 'LRCLIB provider'
```

For a signed device build, configure a valid Apple development team, App Group capability, bundle identifiers, and provisioning first. A generic command shape is:

```sh
xcodebuild \
  -project RokidLyrics.xcodeproj \
  -scheme 'Rokid Lyrics Mock' \
  -configuration Mock-Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

First copy `Config/Local.xcconfig.example` to ignored `Config/Local.xcconfig` and supply the developer team, app/extension bundle IDs, and App Group there. A successful generic build does not prove microphone, Share Extension, routing, Bluetooth, SDK authorization, or display behavior; use a physical device and record evidence under the hardware plan.

## Continuous integration

`.github/workflows/ci.yml` defines a public/mock job on `macos-15`. It:

1. checks out source;
2. selects Xcode 16.4;
3. prints Xcode and Swift versions;
4. installs XcodeGen;
5. enforces the repository's Swift formatting rules;
6. runs `swift test --parallel`;
7. regenerates the Xcode project;
8. builds the **Rokid Lyrics Mock** / `Mock-Debug` generic iOS Simulator configuration with signing disabled and `ROKID_SDK_AVAILABLE=NO`.

The workflow intentionally has no proprietary framework or Rokid credential. [GitHub Actions run 31483973369](https://github.com/Klayertan/rokid-lyrics-ios/actions/runs/31483973369) completed successfully on `main`: formatting, all 72 package tests that existed in that revision, project generation, and the unsigned generic iOS Simulator build passed. The current local suite is 80/80, but those eight additional tests must not be attributed to the historical run. The job did not launch the app, so Simulator-tested status remains “No.”

## Coverage by subsystem

### Domain models and persistence

Tests verify:

- `TrackIdentity` Codable behavior, including recognition playback position;
- progress and display-preference clamping;
- in-memory correction read/write/remove behavior.

### LRC parser

Tests verify:

- `mm:ss.xx` hundredths;
- `mm:ss.xxx` milliseconds;
- one-digit fractions and no fraction;
- hour timestamps;
- multiple timestamps on one line;
- malformed and untimed lines;
- timestamped empty versus physical empty lines;
- Unicode text;
- duplicate timestamp stability and sorting;
- metadata and embedded offset tags.

Fixtures use only synthetic lines such as `First test line` and `Second test line`.

### Timeline and clock

Tests verify:

- before the first lyric;
- exact timestamps;
- positions between lines;
- after the final line;
- positive and negative manual correction;
- embedded LRC offset;
- clamped track progress;
- correction calculation for aligning a selected line;
- monotonic elapsed time;
- pause/resume;
- seek while paused;
- protection against a backward monotonic input;
- stop/reset.

### Lyrics matching

Tests verify:

- exact title and artist;
- rejection of an unrelated artist despite exact title;
- conservative featured-artist syntax;
- canonical Unicode composition;
- Japanese/CJK preservation;
- full-width Latin normalization;
- version conflict penalties;
- preservation of arbitrary parenthetical text;
- album/duration score contribution;
- surfacing ambiguity instead of guessing.

### Synchronization engine

Tests verify:

- the full state sequence through playing and timeline advancement;
- Shazam-estimated playback-position seeding;
- pause/resume stability;
- seek while playing;
- offset adjustment, previous/next navigation, and persistence;
- loading a stored correction when a track is identified;
- `Sync Now` alignment;
- enter/exit resync while preserving prior state;
- invalid-transition errors;
- stop clearing session state;
- generation of previous/current/next display lines.

### Mock display transport

Tests verify:

- connect/send/duplicate-coalesce/clear/disconnect lifecycle;
- rejection of sends while disconnected;
- explicit connection failure;
- failed sends do not record a payload.

These are actor-level mock tests. They do not validate a proprietary SDK, Bluetooth, USB, a physical display, Unicode glyph rendering, or refresh limits.

### LRCLIB provider

Injected HTTP-client tests verify:

- decoding a response shaped like the documented search response;
- the request path and identifying `User-Agent`;
- HTTP failure surfacing;
- invalid JSON surfacing;
- cancellation propagation;
- an injected cache prevents a duplicate request.

No test calls `lrclib.net`, so it cannot establish current service availability or content correctness.

### HTTP retry policy

Serialized URL-protocol tests verify:

- a transient server failure is retried within the configured bound;
- a `Retry-After` value beyond the local retry window is surfaced without an early second request.

They do not wait for or validate real LRCLIB rate limiting.

### CXR-L CustomView payload encoder

SDK-neutral JSON tests verify:

- the open payload uses only the verified layout/text node shapes exercised by the official sample;
- Unicode and JSON control characters round-trip through `JSONEncoder` rather than string interpolation;
- hidden previous/next lines clear their stable nodes;
- font scale changes only verified `sp` text-size properties;
- abstract vertical position maps only to gravity values verified from the platform/sample;
- progress-only model changes do not produce different display JSON.

These tests validate serialization, not SDK calls or display output.

### Share parser

Tests verify:

- explicitly confirmed title/artist fields;
- conservative two-line parsing;
- a spaced dash pattern;
- URL-only input never invents metadata;
- rejection of non-web URL schemes;
- CJK preservation.

These tests construct domain input directly. They do not launch the extension or establish the item types emitted by a current YouTube Music iOS version.

### Shared App Group resolution

Pure resolver tests verify:

- a configured App Group is read from the target Info dictionary;
- surrounding whitespace is removed;
- a supplied fallback is used when the key is absent;
- unresolved Xcode build-setting syntax and non-`group.` identifiers are rejected.

These tests do not prove that an App Group is registered, provisioned, or shared successfully on an iPhone. That requires a signed app/extension device test.

### Diagnostic sanitization

Tests verify that copyable diagnostic helpers:

- redact common credential/token forms, callback query strings, user home-directory names, and email addresses;
- remove credentials, queries, and fragments from public HTTP(S) URLs;
- reject non-web URLs;
- bound arbitrary error text.

Sanitizer tests reduce accidental disclosure risk; they do not replace reviewing a diagnostic report before sharing it or auditing any future SDK/logging integration.

## Important gaps

The automated suite does not yet cover:

- `AVAudioSession` activation, route changes, interruptions, or permission UI;
- real microphone PCM and Shazam catalog matching;
- the Shazam adapter's metadata mapping with an Apple-provided test seam;
- the opt-in live LRCLIB diagnostic action, current service behavior, real rate limiting, and timeout behavior;
- disk-cache expiry/pruning and user-defaults migration;
- SwiftUI UI tests, accessibility automation, or visual snapshots;
- share-extension launch and App Group transfer on an iOS device;
- app suspension/background transitions;
- optional artwork networking;
- the real Rokid SDK adapter;
- discovery, authentication, connection, rendering, reconnection, payload constraints, or device audio;
- battery, heat, long-run drift, or 30-minute stability.

Use [`HARDWARE_TEST_PLAN.md`](HARDWARE_TEST_PLAN.md) for manual and device stages. Never convert an unchecked manual stage into a passed status based only on unit tests.

## Adding tests

- Put provider- and SDK-independent behavior in `RokidLyricsCoreTests`.
- Put service adapters behind injected fakes/stubs in `RokidLyricsServicesTests`.
- Keep hardware and live network access opt-in; never make it part of the default suite.
- Use a manually controlled `MonotonicTimeSource` for timing tests rather than sleeps or wall-clock time.
- Use `URLProtocol` or an injected `HTTPClient` for networking behavior.
- Use `MockRokidDisplayTransport` unless the test is explicitly labeled and configured as a hardware test.
- Use short fictional lyric text only. Do not paste real lyrics into fixtures, snapshots, logs, or failure output.
- Assert cancellation and error behavior, not only success paths.
- When fixing a bug, add the smallest regression test that fails before the fix.

## Pre-release quality gate

Before reporting a release candidate:

1. Run `swift test --parallel` and record the exact pass/fail count.
2. Regenerate the project with XcodeGen.
3. Build the public/mock configuration without a proprietary framework.
4. Build and launch the app and share extension in an iOS Simulator where supported.
5. Build and launch a signed physical-device configuration.
6. Run `xcrun swift-format lint -s -r Sources Tests RokidLyrics RokidLyricsShareExtension`.
7. Search for `TODO` and `FIXME`; document each intentional remainder.
8. Inspect tracked files for credentials, signing assets, lyric dumps, SDK binaries, and user-state files.
9. Review `git diff` and `git status`.
10. Execute applicable hardware stages and attach evidence.
11. Confirm README and status claims match the actual commands and devices used.
12. Verify CI separately; a local pass does not imply GitHub Actions passed.
