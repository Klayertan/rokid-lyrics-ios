# Hardware test plan

## Current execution status

**Plan only. No Rokid hardware stage has been executed or passed as of 2026-08-12.**

The latest 80 passing automated tests cover domain/services behavior, retry policy, SDK-neutral display serialization, the mock transport, App Group setting resolution, and diagnostic sanitization. They are not hardware evidence. Keep every checkbox below unchecked until the named action has been run on the recorded device and the evidence has been reviewed.

Real SDK installation, licensing, authorization, and adapter compilation/link status are tracked in [`ROKID_SDK_NOTES.md`](ROKID_SDK_NOTES.md). The current target-mode validation linked and embedded the genuine dependency graph, but it excluded the asset catalog to bypass this host's missing runtime and was not signed, installed, launched, or connected to glasses. The normal Hardware workspace build remains blocked by the missing iOS 26.5 platform. This plan must not be used to imply that the optional SDK binary is redistributable or that the glasses work before testing.

Use [`PHYSICAL_IPHONE_SETUP.md`](PHYSICAL_IPHONE_SETUP.md) for signing and installation, [`YOUTUBE_MUSIC_DEVICE_TEST.md`](YOUTUBE_MUSIC_DEVICE_TEST.md) for the controlled audio experiment, and a fresh copy of [`DEVICE_TEST_SESSION.md`](DEVICE_TEST_SESSION.md) for each evidence session.

## Evidence standard

For every run, record:

- date/time and tester;
- git commit SHA and whether the worktree was clean;
- scheme, build configuration, compiled build mode, and active runtime mode;
- Xcode version;
- iPhone model and iOS version;
- Rokid glasses model, serial number redacted, firmware version, and companion-app version if applicable;
- official SDK package and framework version;
- connection route/accessories;
- exact steps and expected result;
- observed result, duration, logs, screenshots/video, and relevant Instruments trace;
- pass, fail, blocked, or not run;
- issue link for every failure.

Do not put developer credentials, authorization tokens, full serial numbers, provisioning data, account names, raw microphone audio, or copyrighted lyric text in test evidence. Redact lyric lines from published screenshots/logs.

Use these result meanings:

| Result | Meaning |
| --- | --- |
| Pass | Expected result observed on the documented physical setup. |
| Fail | Test ran and behavior differed from the expected result. |
| Blocked | Test could not run because a named prerequisite/API/credential/device was unavailable. |
| Not run | No attempt was made. This is the default. |

## Prerequisites

- [ ] A clean clone builds in public/mock mode without any proprietary SDK.
- [ ] A current stable Xcode supported by the project is installed.
- [ ] XcodeGen 2.46.0 or later is installed and `xcodegen generate` succeeds.
- [ ] A physical iPhone running iOS 17 or later is paired for development.
- [ ] The developer team, bundle identifiers, App Group, entitlements, and provisioning profiles are valid.
- [ ] Microphone permission can be granted and reset for repeat testing.
- [ ] A Rokid display-capable glasses model and required cable/adapter are present.
- [ ] The exact verified official CXR-L iOS SDK package is installed locally and is not tracked by Git.
- [ ] Required Rokid developer account, application authorization, region, serial-number authorization, firmware, and companion-app prerequisites have been confirmed from official sources or support.
- [ ] The real transport adapter compiles for `iphoneos` with the installed SDK.
- [ ] A test network can reach ShazamKit services, LRCLIB, and artwork hosts.
- [ ] YouTube Music is installed for coexistence/share tests; its app version is recorded.
- [ ] A screen recording/logging method has been chosen that will not expose secrets or full lyrics.

## In-app evidence tools

The current app includes two deliberately separated developer screens:

- **Physical iPhone Tests** reports build/runtime mode, public `AVAudioSession` state and notifications, route port types, microphone activity, human-observed YouTube Music coexistence outcomes, Shazam timing/metadata, synchronization state, and an explicit uncached LRCLIB metadata/availability request. The live request never displays lyric bodies and runs only when the tester taps it.
- **Rokid Hardware Test** exposes isolated connect/disconnect, synthetic static text, clear, counter, Unicode sequence, glasses-microphone metrics, sanitized SDK callback state, and a gated complete-pipeline action. The end-to-end button remains unavailable until the tester confirms the isolated checks and a connection exists.

Copyable reports omit raw PCM, route/device names, callback URLs, credentials, tokens, session IDs, raw SDK logs, lyric bodies, and local coexistence-note text. They still contain track/provider metadata and must be reviewed before sharing. The presence of these controls is implemented/compiled evidence only; it does not mark any checkbox below.

## A. App builds without Rokid connected

Goal: prove the public project remains usable without hardware or a proprietary binary.

- [ ] Clone into a new directory.
- [ ] Confirm no proprietary framework, credentials, certificates, or provisioning profiles are present.
- [ ] Run `swift test --parallel`; record pass/fail count.
- [ ] Run `xcodegen generate`.
- [ ] Build **Rokid Lyrics Mock** / `Mock-Debug` for a generic iOS Simulator with code signing disabled.
- [ ] Launch in an iOS Simulator.
- [ ] Build and install a signed mock-mode app on a physical iPhone with no glasses attached.
- [ ] Confirm launch succeeds and the connection UI says disconnected or mock, not real-connected.
- [ ] Confirm Start/Stop and manual search controls remain available.
- [ ] Confirm the app never claims hardware is connected merely because Mock Mode is active.

Expected: the clone builds, tests, launches, and exposes a clearly labeled mock path with no Rokid SDK dependency.

## B. Mock display works

Goal: validate the complete phone-side presentation/transport contract without glasses.

- [ ] Connect `MockRokidDisplayTransport` from the Connection screen.
- [ ] Load only synthetic LRC text:

  ```text
  [00:01.00]First test line
  [00:02.00]Second test line
  [00:03.00]Third test line
  ```

- [ ] Verify phone Now Playing and glasses simulator show the same previous/current/next state.
- [ ] Verify current-line emphasis is strongest and the display remains uncluttered.
- [ ] Verify `-5`, `-1`, `Sync`, `+1`, `+5`, previous, and next controls update state.
- [ ] Verify pause/resume and Stop.
- [ ] Verify line-count and previous/next visibility settings.
- [ ] Verify font scale and vertical-position simulation.
- [ ] Send the same model repeatedly and confirm duplicate mock payloads are coalesced.
- [ ] Disconnect during playback, keep the timeline running, reconnect, and verify current state is pushed.
- [ ] Copy diagnostics and verify it contains useful state but no secrets.

Expected: simulator, phone preview, synchronization engine, controls, reconnection logic, and mock payload history agree.

## C. Rokid discovery

Goal: verify the exact official device-discovery/availability lifecycle on a phone.

- [ ] Disable Mock Mode and build with the verified real adapter.
- [ ] Put the glasses and required companion environment into the documented ready state.
- [ ] Start discovery/availability using only verified SDK APIs.
- [ ] Record Bluetooth/system permission prompts, if any; do not infer their necessity in advance.
- [ ] Confirm only supported target devices are presented.
- [ ] Confirm cancellation/timeout returns the UI to a stable disconnected state.
- [ ] Power off/unplug the glasses and confirm state changes are observed.
- [ ] Repeat with Bluetooth disabled, denied permission, airplane mode, and missing authorization where applicable.

Expected: discovery/availability behavior matches official SDK documentation and failures are actionable. If the SDK exposes no discovery API and depends on companion-app state, record that exact lifecycle rather than fabricating scanning behavior.

## D. Connect/disconnect repeatedly

Goal: validate lifecycle stability and state accuracy.

- [ ] Connect successfully and record elapsed time.
- [ ] Disconnect from the app and confirm UI and glasses state.
- [ ] Repeat at least 20 connect/disconnect cycles.
- [ ] Disconnect by unplugging/powering down the glasses.
- [ ] Reconnect with automatic reconnect enabled and disabled.
- [ ] Relaunch the app with glasses already available.
- [ ] Background/foreground the app during connecting and connected states.
- [ ] Trigger each recoverable authorization/network/device error available in the setup.
- [ ] Confirm no duplicate sessions, stale connected state, crash, or resource leak.

Expected: the adapter reflects the SDK lifecycle accurately, repeated transitions are stable, and reconnect pushes current visible state only after a confirmed connection.

## E. Push static text

Goal: prove the smallest real display output before attempting a lyric timeline.

- [ ] Connect the physical glasses.
- [ ] Send exactly `Rokid Lyrics Test` through the verified display API.
- [ ] Confirm it appears once and is readable.
- [ ] Record position, clipping, alignment, contrast, and latency.
- [ ] Clear the display and confirm the text disappears.
- [ ] Disconnect and confirm no stale app-owned view remains if the SDK contract promises cleanup.

Expected: static synthetic text opens/updates/clears using verified API calls. Passing this stage does not prove synchronized lyrics.

## F. Rapidly change synthetic lyric lines

Goal: determine safe update cadence and coalescing behavior without copyrighted content.

- [ ] Cycle `First test line`, `Second test line`, and `Third test line` at realistic lyric boundaries for five minutes.
- [ ] Repeat with intentionally faster changes at 2 Hz, 5 Hz, and 10 Hz only if official limits allow it.
- [ ] Confirm production logic sends only visible changes, not every 200 ms evaluation.
- [ ] Measure end-to-end update latency and dropped/coalesced/duplicated updates.
- [ ] Watch for flicker, stale frames, memory growth, SDK errors, disconnects, and overheating.
- [ ] Determine a conservative supported update policy from official constraints and measurements.

Expected: realistic line changes remain readable and stable. Do not adopt a refresh rate beyond verified platform constraints.

## G. Unicode rendering

Goal: verify actual glasses glyph support without assuming installable fonts.

- [ ] English: `Rokid Lyrics Test`
- [ ] Japanese: `日本語 テスト`
- [ ] Chinese: `中文 测试`
- [ ] Korean: `한국어 테스트`
- [ ] Accented Latin: `Crème déjà vu`
- [ ] Mixed script and punctuation: `Test — 日本語 · 中文 · 한국어`
- [ ] Long lines at each supported font scale.
- [ ] Combining and precomposed accented forms.
- [ ] Confirm no tofu boxes, missing glyphs, corruption, unexpected substitution, clipping, or unsafe wrapping.
- [ ] Record exactly which fonts/rendering primitive and device firmware are involved.

Expected: supported scripts render correctly with the platform's existing capabilities. If a script is unsupported, document and surface that limitation; do not claim fonts can be installed unless the SDK explicitly supports it.

## H. Run ShazamKit recognition

Goal: validate the public phone-microphone recognition path and concurrent YouTube Music behavior.

Follow [`YOUTUBE_MUSIC_DEVICE_TEST.md`](YOUTUBE_MUSIC_DEVICE_TEST.md) and record results in [`DEVICE_TEST_SESSION.md`](DEVICE_TEST_SESSION.md). Run H1 with `PhoneMicrophoneAudioCaptureService`. If the real SDK build is available, run H2 separately with `RokidMicrophoneAudioCaptureService`. Record the selected implementation; do not combine their results. The current user-facing mode toggle pairs mock display with phone capture and real display with glasses capture, so a hybrid phone-mic/real-display experiment requires an explicit injected test composition.

### H1. Phone microphone

- [ ] Start YouTube Music before opening/foregrounding Rokid Lyrics.
- [ ] Press Start Lyrics and confirm the microphone-active UI is immediate and obvious.
- [ ] Record whether YouTube Music continues, pauses, ducks, or changes route.
- [ ] Confirm capture stops after success, no match, cancellation, permission denial, and interruption.
- [ ] Verify title and artist returned for several known test tracks without storing lyric text.
- [ ] Record recognition duration and failure rate in quiet and noisy rooms.
- [ ] Repeat the audio-route matrix below.
- [ ] Inspect the app container and confirm no raw audio file was created.

Expected: recognition uses a supported input route, reports failure safely, and never silently records. Device evidence—not `.mixWithOthers` documentation alone—determines coexistence status.

### Required audio-route matrix

| Playback output | Selected input | Continue/pause/duck | Route changed | Shazam result | Notes |
| --- | --- | --- | --- | --- | --- |
| Built-in speaker | Built-in microphone | Not run | Not run | Not run | |
| Wired headphones | Record actual input | Not run | Not run | Not run | |
| Bluetooth A2DP | Record actual input | Not run | Not run | Not run | |
| Bluetooth HFP, if selected/supported | Record actual input | Not run | Not run | Not run | |
| USB audio, if available | Record actual input | Not run | Not run | Not run | |
| AirPlay, if available/supported | Record actual input | Not run | Not run | Not run | |

Also repeat with a call/Siri/alarm interruption and with the app sent to background. Record behavior; do not assume continuity.

### H2. Rokid glasses microphone

- [ ] Build/link/install the exact SDK-enabled app and select non-mock mode.
- [ ] Complete the SDK `.microphone` authorization flow without recording callback URLs/tokens.
- [ ] Confirm the glasses show the synthetic listening state before PCM starts.
- [ ] Record SDK-reported channel count and verify packets decode as 16 kHz little-endian PCM16 per the verified interface/sample behavior.
- [ ] Confirm the app assigns local monotonic receipt times and does not guess undocumented SDK timestamp units.
- [ ] Run Shazam identification with YouTube Music on each relevant iPhone playback route.
- [ ] Record whether starting/stopping the glasses stream changes YouTube Music playback, BLE state, CustomView state, or display responsiveness.
- [ ] Exercise permission denial, session pause/unavailable, disconnect, cancellation, and repeated capture.
- [ ] Inspect app data/logs and confirm no PCM or authentication callback is retained by project code.

Expected: the verified SDK media calls produce usable ephemeral PCM and stop cleanly. No result from H1 may be reused as H2 evidence.

## I. Fetch synchronized lyric metadata

Goal: validate live provider behavior without publishing copyrighted content.

- [ ] Search LRCLIB using metadata returned by ShazamKit.
- [ ] Separately run **Physical iPhone Tests → LIVE LRCLIB TEST** with explicit title/artist input and record only candidate metadata/availability, never lyric bodies.
- [ ] Record request status, elapsed time, candidate count, IDs, scores, and whether plain/synchronized data exists; do not record lyric bodies.
- [ ] Confirm a clear outcome for zero results, one safe result, ambiguity, instrumental, and plain-only records.
- [ ] Confirm cancellation and offline errors reach the UI.
- [ ] Trigger a cache hit and confirm no second request.
- [ ] Confirm expired/pruned cache behavior in a development setup.
- [ ] Exercise `429 Retry-After` with a controlled stub/proxy, not by abusing the public service.
- [ ] Check title/artist variants across English, Japanese, Chinese, Korean, and accented Latin metadata.

Expected: live results map to provider-neutral candidates, ambiguous versions require user choice, and no lyric content enters repository evidence.

## J. Run the complete pipeline

Goal: validate end-to-end behavior from audible music to a real minimal overlay.

- [ ] Establish a confirmed real glasses connection.
- [ ] Start a known track in YouTube Music.
- [ ] Press Start Lyrics in Rokid Lyrics.
- [ ] Observe microphone status, identification, LRCLIB search, candidate selection, LRC parse, clock start, and first display payload.
- [ ] Compare phone previous/current/next lines with the glasses.
- [ ] Measure initial timing error and end-to-end latency.
- [ ] Exercise every manual sync control.
- [ ] Pause/resume the app clock and seek lyrics.
- [ ] Pause/seek/change track in YouTube Music and confirm the documented lack of automatic source-player state access is clear to the user.
- [ ] Disconnect the glasses while lyrics continue, reconnect, and verify the current line is pushed.
- [ ] Stop and confirm microphone, timeline loop, and display are cleared.
- [ ] Repeat using Share Extension confirmation and manual search fallbacks.

Expected: the supported pipeline works with observable error states and no private player access. Passing requires real glasses evidence; a mock/simulator run is insufficient.

## K. Run for 30+ minutes

Goal: characterize stability, drift, power, and thermal behavior.

- [ ] Run the complete pipeline for at least 30 uninterrupted minutes.
- [ ] Record battery percentage before/after and whether the phone is charging.
- [ ] Record thermal state/heat observations and an Instruments energy trace where practical.
- [ ] Count disconnects, reconnect attempts, SDK errors, dropped updates, and crashes.
- [ ] Measure lyric timing error at start, 10, 20, and 30 minutes.
- [ ] Record manual correction frequency and final offset.
- [ ] Confirm display traffic occurs only on visible changes/slow progress refreshes.
- [ ] Monitor app and SDK memory over time.
- [ ] Repeat once with the screen unlocked and once with lock/background transitions if the supported execution model permits it.
- [ ] Repeat connection recovery during the long run.

Expected: results quantify—not merely describe—battery use, heat, disconnects, update traffic, and timing drift. Any suspension or background limitation is documented rather than worked around with an unsupported mechanism.

## Share-extension device matrix

Record the standard items supplied by the current YouTube Music build without relying on a hostname or scraping a link:

| Shared object | Text present | URL present | Type identifiers | Parsed fields | Confirmation required | Result |
| --- | --- | --- | --- | --- | --- | --- |
| Song | Not run | Not run | Not run | Not run | Yes | Not run |
| Video/song mode variant | Not run | Not run | Not run | Not run | Yes | Not run |
| Album | Not run | Not run | Not run | Not run | Yes | Not run |
| Playlist | Not run | Not run | Not run | Not run | Yes | Not run |
| Podcast | Not run | Not run | Not run | Not run | Yes | Not run |
| Timestamp share | Not run | Not run | Not run | Not run | Yes | Not run |

Repeat at least one case in an English locale and one CJK locale. The parser must remain conservative if formats differ.

## Run record template

```text
Stage:
Result: Not run / Pass / Fail / Blocked
Date/time:
Tester:
Commit SHA:
Worktree clean: yes/no
Xcode:
iPhone / iOS:
Glasses / firmware:
SDK package/framework:
Build flags:
Audio route:
YouTube Music version (if used):
Steps performed:
Expected:
Observed:
Duration/measurements:
Redacted evidence location:
Issue links:
Notes:
```

## Exit criteria for public hardware claims

The project may say **real adapter linked against the genuine SDK dependency chain** because the exact target-mode evidence is recorded in [`ROKID_SDK_NOTES.md`](ROKID_SDK_NOTES.md). That wording must also disclose the command-line asset exclusion and that the result was unsigned and never launched. It may say **normal Hardware workspace build passed** only after the asset-complete workspace/scheme command succeeds without that exclusion. It may say **tested on Rokid hardware** only after at least stages C–G and J pass on a named device/firmware setup. It may say **stable for extended use** only after stage K passes with recorded measurements.

Until the physical stages pass, user-facing language must remain: the architecture and mock path are implemented; the real adapter has genuine compile/link evidence but is optional, unlaunched, and not hardware-tested as recorded in `STATUS.md` and `ROKID_SDK_NOTES.md`.
