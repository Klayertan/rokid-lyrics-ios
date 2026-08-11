# Testing

The default automated suite is deterministic, uses fictional lyric text, performs no live network request, and requires neither Rokid hardware nor a proprietary SDK.

## Verified automated result

On 2026-08-11, this command completed successfully in the working repository:

```sh
swift test --parallel
```

Result:

| Runner | Tests | Passed | Failed |
| --- | ---: | ---: | ---: |
| XCTest (`RokidLyricsCoreTests`) | 53 | 53 | 0 |
| Swift Testing (`RokidLyricsServicesTests`) | 19 | 19 | 0 |
| **Total** | **72** | **72** | **0** |

Local validation environment:

- macOS 27.0 (`26A5378j`);
- Xcode 26.6 (`17F113`);
- Apple Swift 6.3.3;
- XcodeGen 2.46.0;
- Swift package deployment platforms: iOS 17 and macOS 14.

This is package compilation and unit-test evidence. Separate compiler-only checks described below cover iOS source/object emission. None of these results is evidence of a linked app bundle, launched iOS Simulator app, physical iPhone behavior, live Shazam/LRCLIB behavior, or Rokid hardware behavior. Those categories are tracked separately in [`STATUS.md`](STATUS.md).

An iOS Simulator build was attempted after generating the project, but `xcodebuild` exited 70 before the Xcode target build because this machine's installation could not load `IDESimulatorFoundation`; the required `/Library/Developer/PrivateFrameworks/CoreSimulator.framework` was absent. Xcode advised updating system content or running first-launch setup. That command is an environment/toolchain failure, not a passing Xcode build; independent compiler-only evidence follows.

Separately, after conditional AppModel and URL-callback wiring was included, the complete main-app Swift source set passed strict Swift 6 arm64 iPhoneOS 17 compilation with whole-module optimization and emitted a 2.1 MB object against the inspected real `RGCxrClient` interface. The check used a temporary empty `RGCoreKit` module solely to satisfy the client interface import. It did not perform the final link, create/sign/install an app bundle, run SDK code, or involve hardware. Report this as **compiled-to-object against actual CXR-L APIs**, never as a linked app or completed/hardware-tested integration. Exact command, artifact, and interface evidence belongs in [`ROKID_SDK_NOTES.md`](ROKID_SDK_NOTES.md).

Independent strict Swift 6 whole-module compilation also emitted:

- a 1,921,672-byte arm64 iOS 17 Simulator object for the public/mock main app;
- a 111,472-byte arm64 iOS 17 Simulator object for the Share Extension.

These simulator-target results prove Swift source/object compilation only. Because the Xcode/CoreSimulator environment is incomplete, neither target was linked into an Xcode-built app/extension bundle or launched. They must be labeled **simulator-target compiled**, not **simulator tested**.

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
  -scheme RokidLyrics \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The generated `.xcodeproj` is an output of `project.yml`; regenerate it after project configuration changes. Do not hand-edit generated project settings.

If `xcodebuild` reports that `IDESimulatorFoundation` cannot load because `CoreSimulator.framework` is missing, repair/complete the Xcode installation using Apple's supported installation/first-launch process before retrying. Do not mark the app compiled or simulator-tested from that failed attempt.

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
  -scheme RokidLyrics \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  -allowProvisioningUpdates \
  build
```

`APPLE_TEAM_ID` is a local shell variable and must never be committed. A successful generic build does not prove microphone, share-extension, routing, Bluetooth, SDK authorization, or display behavior; use a physical device and record evidence under the hardware plan.

## Continuous integration

`.github/workflows/ci.yml` defines a public/mock job on `macos-15`. It:

1. checks out source;
2. selects Xcode 16.4;
3. prints Xcode and Swift versions;
4. installs XcodeGen;
5. enforces the repository's Swift formatting rules;
6. runs `swift test --parallel`;
7. regenerates the Xcode project;
8. builds the generic iOS Simulator configuration with signing disabled and `ROKID_SDK_AVAILABLE=NO`.

The workflow intentionally has no proprietary framework or Rokid credential. The file's presence is not a passing result; no GitHub Actions run had been observed when this document snapshot was written. Record the actual workflow URL and conclusion before changing CI status to passing.

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

## Important gaps

The automated suite does not yet cover:

- `AVAudioSession` activation, route changes, interruptions, or permission UI;
- real microphone PCM and Shazam catalog matching;
- the Shazam adapter's metadata mapping with an Apple-provided test seam;
- live LRCLIB service behavior, real rate limiting, and timeout behavior;
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
6. Run formatting/linting if configured; this repository must not claim a formatter run until one is actually configured and executed.
7. Search for `TODO` and `FIXME`; document each intentional remainder.
8. Inspect tracked files for credentials, signing assets, lyric dumps, SDK binaries, and user-state files.
9. Review `git diff` and `git status`.
10. Execute applicable hardware stages and attach evidence.
11. Confirm README and status claims match the actual commands and devices used.
12. Verify CI separately; a local pass does not imply GitHub Actions passed.
