# Physical-device test session

> **Blank evidence record:** No test result is recorded here. Every **EXPECTED RESULT** is an acceptance target, not evidence that the behavior occurred. Complete **ACTUAL RESULT** and **PASS / FAIL** only while running the named build on the physical setup recorded below.

Use this file with [`PHYSICAL_IPHONE_SETUP.md`](PHYSICAL_IPHONE_SETUP.md), [`YOUTUBE_MUSIC_DEVICE_TEST.md`](YOUTUBE_MUSIC_DEVICE_TEST.md), [`HARDWARE_TEST_PLAN.md`](HARDWARE_TEST_PLAN.md), and [`ROKID_SDK_NOTES.md`](ROKID_SDK_NOTES.md). Make a fresh copy for every device session.

## Session metadata

| Field | Value |
| --- | --- |
| Tester |  |
| Date |  |
| Start/end time and timezone |  |
| Git commit |  |
| Worktree clean or local changes described |  |
| Xcode version/build |  |
| Scheme and build configuration |  |
| App version/build |  |
| Compiled mode shown by app |  |
| Active runtime shown by app |  |
| iPhone model |  |
| iOS version/build |  |
| Microphone permission before session |  |
| Network type |  |
| YouTube Music version |  |
| YouTube Music account/background-play status |  |
| Initial output/input route |  |
| Rokid model, if used |  |
| Rokid firmware, if known |  |
| RGCxrClient package/artifact version, if used |  |
| Rokid AI app version/region, if used |  |
| Evidence folder or issue URL |  |

Do not record a device UDID, full glasses serial number, Apple credential, authorization callback, token, certificate, provisioning profile, raw audio, raw SDK log, or copyrighted lyric text.

## Evidence rules

- Run tests in order. Do not start the complete pipeline before its isolated prerequisites.
- Before each test, stop any prior lyric or microphone session and let the app reach a stable state.
- Mark **PASS** only when the expected result was directly observed on the setup above.
- Mark **FAIL** when the action ran but did not meet its expected result.
- If a prerequisite is missing or the observation is inconclusive, explain it under **ACTUAL RESULT** and leave **PASS / FAIL** blank until a valid rerun.
- Name attachments with the test ID, such as `T03-before.json` and `T03-after.json`.
- Prefer **Settings → Developer Diagnostics → Physical iPhone Tests → COPY DIAGNOSTICS** or **Rokid Hardware Test → COPY DIAGNOSTICS**.
- Review copied reports before sharing. They omit raw PCM, route/device names, callback URLs, credentials, tokens, session IDs, raw SDK logs, and the contents of local coexistence notes. Track metadata and a marker that notes were omitted may remain.
- Never translate compiler, mock, or expected-result text into Simulator-tested or hardware-tested evidence.

## T01 — App installation

**ACTION**

1. Complete [`PHYSICAL_IPHONE_SETUP.md`](PHYSICAL_IPHONE_SETUP.md) with the ignored `Config/Local.xcconfig`.
2. Run `xcodegen generate`, open `RokidLyrics.xcodeproj`, and select **Rokid Lyrics Mock** / **Mock-Debug**.
3. Select the paired physical iPhone and run with automatic signing.
4. Cold-launch Rokid Lyrics from the Home Screen.
5. Open **Settings → Developer Diagnostics → Physical iPhone Tests**.

**EXPECTED RESULT**

Xcode signs the main app and embedded Share extension for the intended team, installs them, and launches without the proprietary SDK. The device-test screen shows **MOCK BUILD**, active runtime **Mock**, and audio source **iPhone microphone**. No microphone starts automatically and no physical-glasses claim appears. Apple documents automatic device registration/provisioning and physical run destinations in [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Commit, worktree state, Xcode, scheme/configuration, app build, iPhone, and iOS versions.
- Xcode result timestamp and first relevant bounded error if installation fails; omit certificates/profiles.
- Sanitized report showing compiled mode, active mode, SDK availability, connection, and microphone state.

## T02 — Microphone permission

**ACTION**

1. Turn Rokid Lyrics microphone access off under **Settings → Privacy & Security → Microphone** if it was previously granted.
2. In Rokid Lyrics, tap **Home → Start Lyrics** and deny the prompt if it appears.
3. Confirm the bounded permission error and stopped capture state.
4. Enable microphone access in iOS Settings.
5. Open **Physical iPhone Tests**, tap **TEST MUSIC COEXISTENCE**, observe for two seconds, then tap **Stop test**.

**EXPECTED RESULT**

The denied attempt captures nothing and explains that permission is required. After the user grants access, capture visibly starts, iOS shows its microphone privacy indicator, and diagnostics report `playAndRecord`, mode `default`, `mixWithOthers`, `defaultToSpeaker`, a valid input, positive sample rate, and at least one input channel. Stop ends capture and clears the privacy indicator. Apple requires explicit recording permission and a usage description: [`AVAudioApplication`](https://developer.apple.com/documentation/avfaudio/avaudioapplication) and [`NSMicrophoneUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription).

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Permission state and error before granting access.
- Before/during/after capture reports: category, mode, options, port types, sample rate/channels, capture state.
- In-app and iOS microphone-indicator appearance/clear timing.

## T03 — YouTube Music coexistence

**ACTION**

1. Use the Mock build, Mock runtime, phone microphone, built-in speaker, and the primary procedure in [`YOUTUBE_MUSIC_DEVICE_TEST.md`](YOUTUBE_MUSIC_DEVICE_TEST.md).
2. Start YouTube Music, wait ten seconds, switch to Rokid Lyrics, and confirm playback remains audible before capture.
3. Open **Physical iPhone Tests** and record the pre-test audio route and **Other audio playing**.
4. Tap **TEST MUSIC COEXISTENCE** once and listen throughout capture.
5. Set only the directly observed **Continued normally**, **Ducked**, **Paused**, **Route changed**, and **Became inaudible** toggles.
6. Stop and verify the post-test route, level, capture state, and privacy indicator.

**EXPECTED RESULT**

YouTube Music is active before the action, phone capture starts/stops, and playback remains acceptably audible without pause, silence, unintended routing, or a crash. Recognition success is evaluated separately. Apple's `mixWithOthers` option expresses mixing intent, not a YouTube Music guarantee: [`playAndRecord`](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord), [`mixWithOthers`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers), and [`defaultToSpeaker`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/defaulttospeaker).

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- YouTube Music version/account/background-play status, route, approximate volume, and audible observations.
- Before/during/after reports with other-audio values, port types, route-change delta, audio events, and capture timing.
- Human observation toggles and local notes recorded separately; copied diagnostics omit the note text. Do not make an audio recording.

## T04 — Shazam recognition

**ACTION**

1. Use the validated coexistence route and a lawful track expected in the Shazam catalog.
2. Tap **TEST MUSIC COEXISTENCE** or **Home → Start Lyrics**.
3. Do not speak, pause, seek, or change route during the approximately eight-second sample.
4. Wait for the ShazamKit action to finish and compare returned title/artist with the audible track.
5. Preserve the first no-match/error before at most one controlled retry.

**EXPECTED RESULT**

ShazamKit returns the correct title and artist with timestamps/latency, or the app exposes a bounded no-match/input/service error. It does not fabricate metadata or a confidence value unavailable from the current public API. A passing positive recognition requires the identity to match the audible track. Apple documents signature/catalog matching through [`SHSession`](https://developer.apple.com/documentation/shazamkit/shsession/).

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Start/match timestamps, monotonic latency, sanitized title/artist, Shazam ID, catalog URL without query/fragment, and error.
- Input/output port types, sample rate/channels, and audible state.
- First-run and retry results kept separate.

## T05 — Live LRCLIB lookup

**ACTION**

1. In **Physical iPhone Tests**, enter a test song title and artist under **Optional live LRCLIB test**.
2. Tap **LIVE LRCLIB TEST**.
3. Record candidate metadata and availability flags.
4. Repeat once with deliberately nonexistent fictional metadata to exercise an empty result without adding lyric content.

**EXPECTED RESULT**

The first action performs a real uncached request and displays metadata/availability only, never lyric text. It returns candidates or a bounded provider/network error. Matching is conservative, and a selected diagnostic result requires synchronized, non-instrumental lyrics. The fictional query returns an honest empty/bounded outcome rather than invented data.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Requested title/artist, latency, candidate count, synced/plain/instrumental flags, scores, selected provider ID/metadata, and error.
- Network type and HTTP/provider failure summary if applicable.
- No plain or synchronized lyric body.

## T06 — Lyric timeline

**ACTION**

1. In **Find Lyrics**, search and select an appropriate synchronized, non-instrumental candidate.
2. Observe position/index for ten seconds.
3. Exercise `-5`, `-1`, **SYNC**, `+1`, `+5`, previous lyric, and next lyric.
4. Pause the lyric clock for five seconds and resume.
5. Pause YouTube Music for five seconds or seek once, return, and manually correct the expected drift.

**EXPECTED RESULT**

The independent monotonic timeline advances while playing, freezes while paused, resumes coherently, and responds to every correction control. It does not claim access to YouTube Music pause/seek state. Manual correction restores useful alignment and persists per track where a stable key exists.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- State, estimated position, global offset, and active index before/after each control.
- Pause duration, source pause/seek, observed drift, applied correction, and post-correction position/index.
- Display character counts only; no lyric text or lyric screenshot.

## T07 — Share Extension

**ACTION**

1. In YouTube Music, use the standard Share action and choose **Share to Rokid Lyrics**.
2. Record whether the host supplied text, a web URL, both, or neither, based only on the extension UI.
3. Verify **Save for Rokid Lyrics** is unavailable until title and artist are nonempty; do not infer missing metadata from a URL.
4. Save a confirmed draft, bring Rokid Lyrics to the foreground, and inspect **Find Lyrics**.
5. Relaunch to confirm the one pending draft is not consumed repeatedly.

**EXPECTED RESULT**

The Share extension accepts supported host items, requires confirmation, does not fetch/scrape a URL, and passes one confirmed draft through the registered App Group. The main app consumes it once and shows the confirmed fields/reference. Apple documents host-supplied extension items and App Group sharing in [Share extensions](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html), [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups), and [`UserDefaults.init(suiteName:)`](https://developer.apple.com/documentation/foundation/userdefaults/init%28suitename%3A%29).

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- YouTube Music version/locale/shared-item type and whether text/URL appeared.
- Prefilled/confirmed fields, sanitized URL origin/path if necessary, handoff result, and repeat-consumption check.
- Main/extension bundle IDs and App Group identifier; no provisioning assets.

## T08 — SDK-linked launch

**ACTION**

1. Complete the optional hardware setup in [`PHYSICAL_IPHONE_SETUP.md`](PHYSICAL_IPHONE_SETUP.md).
2. Open `RokidLyrics.xcworkspace`, select **Rokid Lyrics Hardware** / **Rokid-Hardware-Debug**, and choose the physical iPhone.
3. Build, install, and cold-launch with no claim about glasses behavior.
4. Open **Settings → Developer Diagnostics → Rokid Hardware Test** and confirm Mock Mode is off.

**EXPECTED RESULT**

The app and Share extension link/sign/install, the app launches on arm64 iPhoneOS, and diagnostics show **ROKID HARDWARE BUILD** with active runtime **Rokid Hardware**. This proves a linked/signed device launch only—not authorization, connection, display, microphone, or hardware compatibility. A Simulator is not used because the inspected proprietary framework has no Simulator slice.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Xcode/workspace/scheme/configuration, app build, iPhone/iOS, RGCxrClient and RGCoreKit versions.
- Link/install/launch outcome and first bounded failure, excluding certificates/profiles.
- Sanitized compiled mode, active runtime, initial authorization/session/connection states.

## T09 — Rokid authentication

**ACTION**

1. Confirm the Hardware runtime and required Rokid AI app/environment are present.
2. Open **Rokid Hardware Test** and tap **CONNECT** once.
3. Follow only the official Rokid authorization UI and return through the configured `cxrl` callback.
4. Do not enable SDK logging or copy callback URLs.
5. Observe **Authorization**, **Session**, and sanitized callback events.

**EXPECTED RESULT**

The official flow reaches an authorized/usable session or exposes a bounded failure that identifies the missing external prerequisite without revealing secrets. No token, callback query, session ID, device name, or raw SDK log enters diagnostics. Success is evidence only for the recorded account, region, app, phone, SDK, and firmware environment.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Rokid AI app version/region, SDK version, start/end authorization states, elapsed time, and sanitized events.
- Whether the callback returned to Rokid Lyrics.
- Bounded/redacted error only; never URL query, token, session ID, or full SDK log.

## T10 — Glasses connection

**ACTION**

1. Power and physically attach/pair the intended glasses as required by the official environment.
2. In **Rokid Hardware Test**, tap **CONNECT**.
3. Wait for a terminal connection state, then verify **Connection**, **Session**, **CustomView**, and **Audio stream** fields.
4. Do not send display text yet.

**EXPECTED RESULT**

The adapter reaches **Connected** with coherent authorization/session callbacks, or reports a bounded connection failure without a false connected state. No display or microphone success is inferred from connection alone.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Phone/glasses/firmware/SDK versions, connection start/end state and elapsed time.
- Sanitized authorization/session/connection/CustomView/audio states and events.
- Physical cable/Bluetooth context without personal device names or serial numbers.

## T11 — Static text

**ACTION**

1. Keep the physical glasses connected.
2. In **Rokid Hardware Test**, leave the synthetic field as `Rokid Lyrics Test`.
3. Tap **SEND TEST TEXT** once.
4. Observe both the phone glasses simulator and the physical display for at least five seconds.

**EXPECTED RESULT**

The verified CustomView transport displays exactly `Rokid Lyrics Test` once, with no fabricated extra content, and diagnostics record the synthetic update. The display remains stable until another explicit update or clear action.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Send timestamp/latency, connection and CustomView state, sanitized display events, last synthetic text.
- Exact visible synthetic string, alignment, clipping, flicker, duplication, and persistence observations.

## T12 — Clear display

**ACTION**

1. Begin with the static text from the preceding test visible.
2. Tap **CLEAR DISPLAY** once.
3. Observe the physical display and phone simulator for at least five seconds.

**EXPECTED RESULT**

The synthetic CustomView content is removed from both the real transport output and phone model without disconnecting the session or leaving stale text. Diagnostics record a successful clear or a bounded error.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Clear timestamp/latency, pre/post CustomView and connection state, sanitized event.
- Whether any text, ghosting, stale frame, flicker, or unintended disconnect remained.

## T13 — Repeated updates

**ACTION**

1. Keep the glasses connected and display clear.
2. Tap **SEND COUNTER** ten times at approximately two updates per second.
3. Repeat ten times at approximately one update per second.
4. Stop input and observe the final value for five seconds.

**EXPECTED RESULT**

Distinct synthetic counter values arrive in order without a crash, runaway update loop, corrupted payload, or unnecessary per-frame traffic. The final displayed value matches the final requested counter. Any verified rate/payload limit is respected rather than guessed.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Requested count/rate, received visible sequence, missed/duplicated/out-of-order values, final value.
- Sanitized display events, failures, disconnects, flicker, latency, and thermal observation.

## T14 — English text

**ACTION**

1. Enter `Hello Rokid` in **Synthetic test text**.
2. Tap **SEND TEST TEXT**.
3. Inspect the physical display at normal viewing distance.

**EXPECTED RESULT**

The complete English string `Hello Rokid` renders legibly with correct characters, ordering, spacing, and no clipping on the tested hardware/firmware.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Exact synthetic string, rendered/missing/replaced characters, legibility, clipping, alignment, and firmware.
- Sanitized display event and CustomView/connection state.

## T15 — Japanese text

**ACTION**

1. Enter `日本語テスト` in **Synthetic test text**.
2. Tap **SEND TEST TEXT**.
3. Inspect every glyph on the physical display.

**EXPECTED RESULT**

The complete Japanese synthetic string `日本語テスト` renders legibly with correct glyphs/order and no replacement boxes or clipping on the tested hardware/firmware. This does not imply that fonts can be installed or that all Japanese glyphs are supported.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Exact synthetic string, each missing/replaced glyph position, legibility, clipping, alignment, and firmware.
- Sanitized display event and CustomView/connection state.

## T16 — Chinese text

**ACTION**

1. Enter `中文测试` in **Synthetic test text**.
2. Tap **SEND TEST TEXT**.
3. Inspect every glyph on the physical display.

**EXPECTED RESULT**

The complete Chinese synthetic string `中文测试` renders legibly with correct glyphs/order and no replacement boxes or clipping on the tested hardware/firmware. The result is limited to these synthetic characters and this hardware/firmware.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Exact synthetic string, each missing/replaced glyph position, legibility, clipping, alignment, and firmware.
- Sanitized display event and CustomView/connection state.

## T17 — Korean text

**ACTION**

1. Enter `한국어 테스트` in **Synthetic test text**.
2. Tap **SEND TEST TEXT**.
3. Inspect every glyph and the space on the physical display.

**EXPECTED RESULT**

The complete Korean synthetic string `한국어 테스트` renders legibly with correct glyphs/order/spacing and no replacement boxes or clipping on the tested hardware/firmware. The result is limited to these synthetic characters and this hardware/firmware.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Exact synthetic string, each missing/replaced glyph position, spacing, legibility, clipping, alignment, and firmware.
- Sanitized display event and CustomView/connection state.

## T18 — Disconnect/reconnect

**ACTION**

1. Connect and display a synthetic counter value.
2. Tap **DISCONNECT** and confirm the terminal state.
3. Wait five seconds, tap **CONNECT**, and observe authorization/session/connection recovery.
4. Verify whether the current display state is repushed after reconnection.
5. Repeat the disconnect/reconnect cycle three times.

**EXPECTED RESULT**

Each explicit disconnect leaves a truthful disconnected state. Each reconnect either returns to a coherent connected session and repushes current visible state or reports a bounded failure. No duplicate session, frozen connecting state, crash, or false connected state occurs.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Per-cycle disconnect/connect timestamps, duration, terminal states, authorization/session/CustomView events.
- Display state before disconnect and after reconnect, duplicate updates, failures, and required manual recovery.

## T19 — Glasses microphone if supported

**ACTION**

1. Confirm Hardware runtime, Mock Mode off, authorization complete, and glasses connected.
2. Open **Rokid Hardware Test** and tap **TEST GLASSES MICROPHONE**.
3. Wait up to the session's agreed diagnostic timeout for counters to advance.
4. Observe state, stream connection, sample rate, channels, bytes, frames, buffers, and duration.
5. Tap **STOP GLASSES MICROPHONE**.

**EXPECTED RESULT**

If the official SDK/environment supports microphone PCM on this setup, the test reports a connected stream, positive sample rate/channel count, and monotonically increasing byte/frame/buffer counters, then stops cleanly. Raw PCM remains in memory and absent from diagnostics. If the capability is unavailable, the app reports that bounded limitation and does not fabricate frames or recognition routing.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Capability/prerequisite status, stream state, sample rate, channels, bytes, frames, buffers, duration, stop result.
- Sanitized SDK audio events and bounded error; no audio content or raw SDK log.
- ShazamKit routing field, explicitly noting that the isolated PCM test itself does not claim recognition.

## T20 — Complete lyrics pipeline

**ACTION**

1. Run only after T09–T19 applicable isolated checks pass on this setup.
2. In **Rokid Hardware Test**, connect the glasses and enable **I completed the isolated connection, text, clear, update, and Unicode checks** only if true.
3. Start lawful audible music in YouTube Music on a previously characterized route.
4. Tap **START COMPLETE PIPELINE**.
5. Observe glasses PCM, ShazamKit identity, LRCLIB resolution, timeline, and physical display.
6. Apply one manual sync correction, then Stop, clear, and disconnect.

**EXPECTED RESULT**

The supported components compose end to end: glasses PCM reaches recognition, ShazamKit returns the correct track, LRCLIB yields an explicitly safe synchronized result, the monotonic timeline advances/corrects, and changed lyric state reaches the physical display without per-frame transport traffic. Any missing stage surfaces an honest bounded error; no partial run is described as a complete hardware success.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Start/end reports and stage timestamps/latencies.
- Glasses PCM counters; sanitized Shazam metadata; LRCLIB candidate/selection/line-count data; sync position/offset/index.
- Connection/CustomView/display character-count summaries, correction applied, stop/clear/disconnect confirmation.
- No raw audio, lyric text, callback secret, or raw SDK log.

## T21 — 30-minute stability

**ACTION**

1. Begin only after the complete pipeline passes once on this exact setup.
2. Run for at least 30 minutes, using at least three explicit Stop/Start recognition cycles as tracks change; the MVP does not claim automatic cross-app track-change detection.
3. Include one controlled glasses disconnect/reconnect.
4. Monitor battery, heat/thermal state, responsiveness, disconnects, errors, drift, manual corrections, and display-update behavior.
5. At the end, stop capture, clear display, disconnect, and confirm privacy indicators clear.

**EXPECTED RESULT**

For at least 30 minutes, the app remains responsive, exposes failures honestly, keeps transport updates bounded to visible-state changes/slow progress refreshes, stops privacy-sensitive capture, and recovers from the controlled reconnect. Battery drain, heat, disconnect frequency, timing drift, and update behavior remain within the acceptance criteria the tester records before the run. Passing applies only to the exact device/firmware/app/SDK configuration documented here.

**ACTUAL RESULT**



**PASS / FAIL**



**DIAGNOSTIC DATA TO CAPTURE**

- Reports at start, every recognition cycle, after reconnect, and end.
- Start/end battery percentage, thermal/heat observations, disconnect count/duration, errors, drift, corrections, and approximate display-update cadence.
- Recognition/LRCLIB latencies and outcomes per cycle.
- Final confirmation: microphone stopped, privacy indicator cleared, display cleared, and glasses disconnected.

## Session closeout

- Review T01 through T21 for blank, failed, or inconclusive results.
- Keep unrun or inconclusive items unclaimed.
- Verify attachments contain no raw audio, lyric text, private callback URL, credential, device identifier, or raw SDK log.
- Report implemented, compiled, unit-tested, Simulator-tested, and hardware-tested evidence separately.
- Update [`STATUS.md`](STATUS.md) only after evidence review; this blank template alone changes no project status.

## Official source basis

- Apple: [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- Apple: [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- Apple: [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- Apple: [ShazamKit service setup](https://developer.apple.com/help/account/services/shazamkit/)
- Apple: [`AVAudioApplication`](https://developer.apple.com/documentation/avfaudio/avaudioapplication)
- Apple: [`AVAudioSession.playAndRecord`](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord)
- Apple: [`AVAudioSession.CategoryOptions.mixWithOthers`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers)
- Apple: [`AVAudioSession.CategoryOptions.defaultToSpeaker`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/defaulttospeaker)
- Apple: [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)
- Apple: [Responding to audio route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)
- Apple: [`UIBackgroundModes`](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes)
- Apple: [Share extensions](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)
- Google: [Explore YouTube Music Premium benefits](https://support.google.com/youtubemusic/answer/9266556?hl=en)
- Google: [Share music & podcasts](https://support.google.com/youtubemusic/answer/9198182?hl=en)
