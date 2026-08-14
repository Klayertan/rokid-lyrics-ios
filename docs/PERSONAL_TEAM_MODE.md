# Personal Team mode

Last verified: 2026-08-14

## Purpose

**Rokid Lyrics Personal** lets you install and use as much of Rokid Lyrics as possible on your own iPhone, signed with a free Apple ID ("Personal Team" in Xcode), without enrolling in the paid Apple Developer Program. It coexists with **Rokid Lyrics Mock** and **Rokid Lyrics Hardware**; neither existing scheme is changed or removed. See [Physical iPhone setup → Free Apple Account / Personal Team](PHYSICAL_IPHONE_SETUP.md#free-apple-account--personal-team) for the exact Xcode steps.

Personal mode is a **separate Xcode target** (`RokidLyricsPersonal`), not a flag on the existing app target. It has no dependency on `RokidLyricsShareExtension` and its entitlements file (`RokidLyrics/Resources/RokidLyricsPersonal.entitlements`) declares no capabilities at all — no App Groups, no ShazamKit entry. Nothing is requested during signing that a free account might reject.

## What works

Verified by a target-mode compile+link (`xcodebuild -target RokidLyricsPersonal -sdk iphoneos`, unsigned) on 2026-08-14. This proves the app **compiles and links**; it does not prove Personal Team **signing**, **installation**, or **launch**, which require your own physical iPhone and Apple ID (see [Critical accuracy](#critical-accuracy) below).

- Normal SwiftUI app: Home, Now Playing, Connection, Search, Settings, and Developer Diagnostics.
- Manual lyrics search against LRCLIB (`Find Lyrics` tab), with the same conservative title/artist/album/duration matching as every other mode.
- LRCLIB synchronized-lyrics fetch and caching — identical `LRCLibLyricsProvider` used everywhere.
- The full `LyricsSynchronizationEngine`: monotonic clock, pause/resume, offset, previous/next-line, and per-track corrections.
- The mock Rokid display/simulator (`MockRokidDisplayTransport`) — Personal mode defaults `Mock Mode` on, same as Mock scheme.
- The paste-based share fallback described under [Personal workflow](#personal-workflow) below, reusing the existing `SharedTrackParser`.
- Developer Diagnostics reports build mode and per-capability availability (see [`ARCHITECTURE.md`](ARCHITECTURE.md) for the general diagnostics-sanitization policy).

## What may be unavailable

Only the following are actually gated by build/signing configuration. Everything else in [What works](#what-works) is unconditional.

| Capability | Status under Personal Team | Evidence |
| --- | --- | --- |
| **Share Extension** | **Confirmed unavailable.** The Personal target has no dependency on `RokidLyricsShareExtension`; it is never built or embedded by the `Rokid Lyrics Personal` scheme. | Structural: `project.yml` target definition and the built `.app` (no `PlugIns/` directory), inspected 2026-08-14. |
| **App Group** | **Confirmed unavailable by design**, and independently corroborated as blocked for free/Personal Team signing. `RokidLyricsPersonal.entitlements` declares no `com.apple.security.application-groups` key. | This project's design (no entitlement declared). Independently, an Apple Developer Forums thread (`developer.apple.com/forums/thread/718388`) shows Xcode rejecting a capability for a personal development team with the literal message *"Personal development teams, including '\<name\>', do not support the Push Notifications capability."* That is the confirmed, reproducible mechanism Xcode uses to gate capabilities per team type. Multiple independent community write-ups describe App Groups as blocked by that same mechanism for personal teams, though this project did not itself capture the exact App-Groups error string on a live personal team. Apple's own capability guidance says available capabilities depend on program membership: [Adding capabilities to your app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app), [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/). |
| **ShazamKit automatic recognition** | **Unverified.** See [ShazamKit status](#shazamkit-status) below. Defaults to compiled-in; a compile-time escape hatch exists if your signing rejects it. | Not yet tested with an actual Personal Team on a physical device. |
| **App Store / TestFlight distribution** | **Confirmed unavailable.** A free Apple ID cannot submit to App Store Connect; this is standard, well-documented Apple account behavior, unrelated to this project. | Out of scope for this document; Personal mode is Xcode-sideload-only by design. |
| **Real Rokid SDK (RGCxrClient/RGCoreKit)** | **Unverified**, but plausible. See [Personal + Rokid hardware](#personal--rokid-hardware-unverified) below. | [`ROKID_SDK_NOTES.md`](ROKID_SDK_NOTES.md) documents no Apple capability or entitlement requirement for the SDK beyond ordinary device code signing. |

Mark nothing above "available" or "unavailable" without one of these two kinds of evidence: this project's own build/entitlement configuration (structural), or Apple's official documentation/observed Xcode behavior (external). Community forum reports are cited as corroborating evidence, not as a substitute for an actual on-device test.

### ShazamKit status

This project has never added a `com.apple.developer.shazamkit` entitlement key — see [`README.md` → Apple and ShazamKit configuration](../README.md#apple-and-shazamkit-configuration) and [`PHYSICAL_IPHONE_SETUP.md`](PHYSICAL_IPHONE_SETUP.md). Apple's ShazamKit setup guide describes enabling ShazamKit as an **App ID service** in **Certificates, Identifiers & Profiles → App Services** ([Enable ShazamKit for an App ID](https://developer.apple.com/help/account/services/shazamkit/)), the same portal area where App Groups is configured and where personal/free accounts are known to be restricted for other capabilities.

Because this project's own signing has never requested that App ID service, it is genuinely unknown whether:

1. A Personal Team can reach and enable the ShazamKit App ID service at all, or
2. `SHSession.result(from:)` catalog matching (a network call to Apple's service) requires that service to be enabled to succeed, independent of any local entitlement.

Given that ambiguity, `Rokid Lyrics Personal` compiles **with** ShazamKit by default (`ROKID_LYRICS_SHAZAM_AVAILABLE = YES` in [`Config/Personal.xcconfig`](../Config/Personal.xcconfig)) rather than assuming failure. If your own Personal Team signing rejects it, or catalog matching fails in a way that looks like a service/authorization error rather than an ordinary no-match, add to your gitignored `Config/Local.xcconfig`:

```xcconfig
ROKID_LYRICS_SHAZAM_AVAILABLE = NO
ROKID_LYRICS_SHAZAM_COMPILATION_CONDITION =
```

then run `xcodegen generate` again. `AppCapabilities.shazamRecognitionAvailable` becomes `false`, `AppModel` swaps in `UnavailableTrackIdentificationService` instead of `ShazamTrackIdentificationService`, and the Home screen shows the manual-search fallback instead of attempting recognition — see [`AppModel.startLyrics()`](../RokidLyrics/App/AppModel.swift) and [`HomeView`](../RokidLyrics/Features/Home/HomeView.swift). No repeated runtime errors: the app never invokes the microphone/recognition pipeline when this flag is off.

### Personal + Rokid hardware (unverified)

[`ROKID_SDK_NOTES.md`](ROKID_SDK_NOTES.md) contains no mention of an App Group, push, or other Apple capability requirement for `RGCxrClient`/`RGCoreKit` — only ordinary arm64 iPhoneOS code signing. That is evidence *against* a capability blocker, not evidence that Personal Team signing has actually succeeded with the SDK linked; the real SDK has never been signed, installed, or hardware-tested even under a paid team (see [`STATUS.md`](STATUS.md)). A future `ROKID_SDK_AVAILABLE = YES` override of `Config/Personal.xcconfig` (in a local, uncommitted copy, or a future dedicated config) is plausible but out of scope for this milestone. Do not attempt it before completing the ordinary Personal + Mock path on your device.

## Personal workflow

Personal mode's manual flow is the same shape as every other mode's fallback path, just promoted to the primary path when ShazamKit is unavailable:

```text
YouTube Music playing
  ↓
Open Rokid Lyrics (Personal)
  ↓
Search / Paste Song  (Search tab: title+artist fields, or paste shared text/link)
  ↓
Select result
  ↓
LRCLIB synced lyrics
  ↓
manual synchronization (Sync Now / ±1 / ±5 / previous/next line)
  ↓
mock (or, if signed with the real SDK, Rokid) display
```

Because Personal mode has no Share Extension, `SearchView` shows a **Paste a shared song** field whenever `capabilities.shareExtensionAvailable` is `false`. Pasting copied YouTube Music share text or a link runs it through the existing `SharedTrackParser` — the same conservative, tested parser the Share Extension itself uses (see [`SharedTrackParserTests`](../Tests/RokidLyricsServicesTests/SharedTrackParserTests.swift)). It never reverse-engineers YouTube Music, scrapes a URL, or fabricates a match when the pasted payload lacks enough information; you confirm or correct the fields exactly as you would with the Share Extension.

## Upgrade path

Nothing about Personal mode is destructive to the other modes. If you later enroll in the paid Apple Developer Program:

1. Keep using `Rokid Lyrics Mock` or set up `Rokid Lyrics Hardware` following [`PHYSICAL_IPHONE_SETUP.md`](PHYSICAL_IPHONE_SETUP.md) as normal — nothing about those schemes changes because Personal mode exists.
2. Your `Config/Local.xcconfig` identity values (`ROKID_LYRICS_BUNDLE_ID`, `ROKID_LYRICS_APP_GROUP`, etc.) are shared across all three schemes; only `ROKID_LYRICS_DEVELOPMENT_TEAM` needs to change to your paid team.
3. `Rokid Lyrics Personal` keeps working afterward too — nothing about a paid enrollment removes a free Personal Team from Xcode's account list, so the Personal scheme remains available for quick sideloading without a full Mock/Hardware signing pass.

## Configuration reference

All defaults live in [`Config/Base.xcconfig`](../Config/Base.xcconfig); [`Config/Personal.xcconfig`](../Config/Personal.xcconfig) overrides only what Personal mode actually changes.

| Setting | Base default | Personal value | Effect |
| --- | --- | --- | --- |
| `ROKID_LYRICS_BUILD_MODE` | `mock` | `personal` | Keys `AppSettings`'s per-build-mode Mock Mode storage bucket so Personal's toggle never collides with Mock's; shown as `Build Mode` in Diagnostics. |
| `ROKID_LYRICS_PERSONAL_TEAM_MODE` | `NO` | `YES` | Surfaced in Diagnostics; does not itself gate any feature. |
| `ROKID_LYRICS_SHARE_EXTENSION_AVAILABLE` | `YES` | `NO` | Drives `AppCapabilities.shareExtensionAvailable`; the actual exclusion is structural (no target dependency). |
| `ROKID_LYRICS_APP_GROUP_AVAILABLE` | `YES` | `NO` | Drives `AppCapabilities.appGroupAvailable`; the actual exclusion is structural (no entitlement key). |
| `ROKID_LYRICS_SHAZAM_AVAILABLE` | `YES` | `YES` (overridable in `Local.xcconfig`) | Runtime half of the ShazamKit gate; see [ShazamKit status](#shazamkit-status). |
| `ROKID_LYRICS_SHAZAM_COMPILATION_CONDITION` | `ROKID_LYRICS_SHAZAM_AVAILABLE` | inherited | Compile-time half of the same gate (`#if` token spliced into `SWIFT_ACTIVE_COMPILATION_CONDITIONS`). |
| `ROKID_SDK_AVAILABLE` | `NO` | `NO` | Unchanged from Mock; see [Personal + Rokid hardware](#personal--rokid-hardware-unverified). |

`AppCapabilitiesResolver` (in `RokidLyricsCore`, unit tested in [`AppCapabilitiesTests`](../Tests/RokidLyricsCoreTests/AppCapabilitiesTests.swift)) turns the Info.plist-injected values above, plus the two compile-time facts, into the `AppCapabilities` struct that `AppModel` and every view read.

## Critical accuracy

This document and the app's own Diagnostics screen distinguish **compiled** from **signed/installed/launched/hardware-tested**, matching the rest of this repository's evidence discipline (see [`STATUS.md`](STATUS.md)). As of 2026-08-14:

- **IMPLEMENTED**: yes — target, scheme, capability abstraction, manual fallback, docs.
- **COMPILED / LINKED**: yes — `xcodebuild -target RokidLyricsPersonal -sdk iphoneos`, unsigned, succeeded.
- **SIGNED**: not yet — requires your own Apple ID added to Xcode as a Personal Team.
- **INSTALLED / LAUNCHED**: not yet — requires your own physical iPhone.
- **HARDWARE TESTED**: not applicable to Personal mode's primary goal (mock display only, unless you separately pursue the unverified [hardware path](#personal--rokid-hardware-unverified)).

Do not read "compiles" as "works on Personal Team." Follow [Physical iPhone setup → Free Apple Account / Personal Team](PHYSICAL_IPHONE_SETUP.md#free-apple-account--personal-team) to complete the remaining, external steps yourself.
