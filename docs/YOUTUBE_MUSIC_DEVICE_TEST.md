# YouTube Music physical-device test

> **Procedure status:** No test in this document has been executed or passed. This is the controlled procedure for collecting the first physical-iPhone evidence. Put results in [`DEVICE_TEST_SESSION.md`](DEVICE_TEST_SESSION.md), not in this procedure.

## Purpose

The primary experiment is named **TEST MUSIC COEXISTENCE**. It answers a narrow question:

> While YouTube Music is already playing on the same iPhone, can Rokid Lyrics activate its supported microphone capture path without pausing, silencing, or unacceptably rerouting that playback?

This test does **not** attempt to read YouTube Music's title, artist, queue, elapsed time, pause state, or raw digital audio. YouTube Music is only the source of sound that may reach a supported microphone input.

Keep these outcomes separate:

1. **Music coexistence:** Did YouTube Music keep playing acceptably while the microphone session was active?
2. **Capture:** Did Rokid Lyrics start and stop its supported input path?
3. **Recognition:** Did ShazamKit identify the acoustically captured audio?
4. **Lyrics:** Did LRCLIB return a safe synchronized candidate?
5. **Synchronization:** Did the independent lyric clock remain acceptably aligned?

A Shazam no-match does not by itself fail coexistence. Conversely, a Shazam match does not prove that playback never ducked, paused, or rerouted.

## Supported boundary

Rokid Lyrics intentionally does not use private YouTube APIs, scraping, MediaRemote, undocumented notifications, or private iOS frameworks. Apple's public description of [`MPNowPlayingInfoCenter`](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter) is an object for setting Now Playing information for media an app itself plays; this project does not treat it as a supported cross-app playback-state reader.

The supported phone path is:

```text
YouTube Music playback that remains audible
  -> iPhone microphone selected by iOS
  -> short in-memory PCM capture
  -> ShazamKit acoustic signature and catalog match
  -> LRCLIB runtime metadata/lyrics request
  -> independent monotonic lyric clock
```

Apple documents the microphone as a normal input source for an `SHSignatureGenerator`: [Generating a signature from an audio buffer](https://developer.apple.com/documentation/shazamkit/generating-a-signature-from-an-audio-buffer). Apple's [`SHSession`](https://developer.apple.com/documentation/shazamkit/shsession/) documentation describes matching a captured signature against the Shazam catalog and requires the app's App ID to have catalog access enabled.

## What the current phone implementation requests

When the public Mock build runs the phone-microphone path, the code:

- requests recording permission with `AVAudioApplication`;
- configures `AVAudioSession` with category `.playAndRecord` and mode `.default`;
- includes `.mixWithOthers`;
- includes `.defaultToSpeaker`;
- activates the session;
- installs an `AVAudioEngine` input tap;
- keeps PCM in a bounded in-memory stream and does not intentionally write it to disk;
- removes the tap, stops the engine, and deactivates the session with `notifyOthersOnDeactivation` when capture ends.

Apple calls `.playAndRecord` appropriate for input and output and explains that it is nonmixable unless `mixWithOthers` is supplied: [`playAndRecord`](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord). Apple says `mixWithOthers` indicates that a session mixes with audio from other active apps: [`mixWithOthers`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers).

Those semantics are necessary context, not a YouTube Music compatibility guarantee. The other app's session, the selected input/output route, the phone model, attached accessories, iOS version, and YouTube Music version still determine observable behavior.

The `.defaultToSpeaker` option is especially important to measure. Apple documents it as changing `.playAndRecord` routing toward the built-in speaker and notes that it can keep the built-in mic/speaker route even when an accessory is connected: [`defaultToSpeaker`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/defaulttospeaker). Therefore, never assume a wired, Bluetooth, USB, or AirPlay route remains selected after capture starts—record the actual route.

## Prerequisites

Complete [`PHYSICAL_IPHONE_SETUP.md`](PHYSICAL_IPHONE_SETUP.md) first. For the primary coexistence run, use:

- the **Rokid Lyrics Mock** scheme and `Mock-Debug` configuration;
- a signed physical iPhone running iOS 17 or later;
- **Settings → Developer / Mock Mode** on;
- **Settings → Developer Diagnostics → Physical iPhone Tests** showing:
  - `Compiled mode: MOCK BUILD`;
  - `Active mode: Mock`;
  - `Audio source: iPhone microphone`;
- microphone permission granted;
- a network that can reach Apple's Shazam service and LRCLIB;
- YouTube Music updated to the version under test;
- a YouTube Music account/configuration that can keep music playing while another app is foregrounded;
- the built-in iPhone speaker selected for the primary run;
- a moderate, clearly audible volume in a quiet environment.

Google documents background play for music while using other apps as a YouTube Music Premium benefit, with regional/product variations: [Explore YouTube Music Premium benefits](https://support.google.com/youtubemusic/answer/9266556?hl=en). If playback stops merely because you leave YouTube Music—before Rokid Lyrics starts capture—the coexistence precondition was not met. Record the run as inconclusive or blocked; do not attribute that stop to Rokid Lyrics.

Choose music you are lawfully allowed to play and that is reasonably likely to exist in the Shazam catalog. Do not put a real lyric excerpt, audio recording, or lyric screenshot in the repository. It is acceptable for a private test record to identify the track by title and artist, but review that metadata before sharing diagnostics.

## Before each run

Record these values in the session template:

- date, time, timezone, tester;
- Git commit and whether the worktree contains local changes;
- Xcode version and configuration;
- iPhone model and iOS build;
- Rokid Lyrics version/build number;
- YouTube Music version, account tier, and background-play setting;
- output route before opening Rokid Lyrics;
- intended microphone/input route;
- network type;
- approximate volume;
- whether any call, alarm, Siri request, screen recording, casting session, or other audio app is active.

Avoid iOS screen recording during the primary run. It can introduce another capture/session participant and may store copyrighted audio. Use the app's sanitized text report and written observations instead.

## Primary TEST MUSIC COEXISTENCE flow

Run this first with the built-in iPhone speaker and no wired, Bluetooth, USB, or AirPlay accessory connected.

### A. Establish the baseline

1. Force no state changes in Rokid Lyrics; simply leave it installed and stopped.
2. Open YouTube Music.
3. Start a music track.
4. Let it play for at least 10 seconds so a brief startup/buffering event is not mistaken for a coexistence effect.
5. Confirm the sound is coming from the built-in speaker at a moderate volume.
6. Note whether playback is smooth and at what approximate volume.
7. Switch to Rokid Lyrics using the app switcher.
8. Before pressing any recognition control, listen for at least 5 seconds.
9. If playback has already stopped, return to YouTube Music, verify the account/background-play setting, and end this run as a failed precondition.

### B. Open the controlled test screen

1. In Rokid Lyrics, open **Settings**.
2. Confirm **Developer / Mock Mode** is on.
3. Tap **Developer Diagnostics**.
4. Tap **Physical iPhone Tests**.
5. In **Build and runtime**, confirm **MOCK BUILD**, **Mock**, and **iPhone microphone**.
6. In **Audio session**, record the category, mode, options, route, input device, sample rate, channel counts, **Other audio playing**, last interruption, and route-change count.
7. Confirm YouTube Music remains audible immediately before the test action.

`Other audio playing` is a public `AVAudioSession` observation, not YouTube Music metadata. It can support the record, but the tester's direct audible observation remains necessary.

### C. Run the action

1. Under **YouTube Music coexistence**, tap **TEST MUSIC COEXISTENCE** once.
2. If iOS requests microphone access, read the purpose string and tap **Allow** for this test.
3. Do not press controls in YouTube Music during the recognition interval.
4. Listen continuously while Rokid Lyrics reports capture/listening. The current recognition adapter normally accumulates about eight seconds of microphone audio before asking ShazamKit for a result.
5. Observe whether playback:
   - continued at the same apparent level;
   - became quieter;
   - paused or stopped;
   - changed output route;
   - became inaudible;
   - produced feedback, echo, or severe distortion.
6. If the app navigates to Lyrics Now Playing or Search after recognition, return to **Settings → Developer Diagnostics → Physical iPhone Tests**.
7. Under **Record what you heard**, set only the toggles you directly observed:
   - **Continued normally**;
   - **Ducked**;
   - **Paused**;
   - **Route changed**;
   - **Became inaudible**.
8. Add a short note only when needed. Do not paste a token, callback URL, email address, SDK log, or lyric text.
9. If recognition continues unexpectedly or privacy requires immediate stop, tap **Stop test**.

Leave all audible-result toggles off if the result is genuinely unknown, and say `inconclusive observation` in the note. Do not select **Continued normally** merely because Shazam matched.

### D. Capture evidence

1. Read **Test state**, **Other audio at start**, and **Other audio now**.
2. Re-read the **Audio session** route, options, interruption, and route-change fields.
3. Read the **ShazamKit** state and latency. A title/artist is recognition evidence, not coexistence evidence.
4. Read **Current pipeline LRCLIB** and **Synchronization** if the pipeline advanced that far.
5. Expand **Audio notification log** and note any category, route, interruption, or secondary-audio event at the test time.
6. Tap **COPY DIAGNOSTICS**.
7. Paste into a private text editor first.
8. Review the report for track metadata, provider IDs, catalog URLs, and errors before attaching it to an issue or session record. The contents of the local notes field are not copied; the report can contain only a marker that notes were omitted.
9. Put the sanitized report's filename or attachment reference in the applicable test's **DIAGNOSTIC DATA TO CAPTURE** record. Do not paste a large report directly into this procedure.

The report intentionally omits route/device names, raw PCM, callback URLs, credentials, tokens, and SDK logs. It can still contain song metadata and sanitized service information, so human review remains required.

### E. Stop and verify deactivation

1. If lyrics are active, return to **Home** and tap **Stop**.
2. Return to **Physical iPhone Tests**.
3. Confirm **Microphone capture** reports **Stopped**.
4. Confirm the app no longer shows its microphone-active status.
5. Confirm the iOS microphone privacy indicator clears after capture ends.
6. Continue listening to YouTube Music for at least 10 seconds.
7. Record whether volume or route returns to its pre-test state.

## Acceptance rules for the built-in-speaker run

Mark the coexistence portion **PASS** only when all of the following are directly observed:

- YouTube Music was audible after switching apps and immediately before the test action.
- The diagnostic snapshot reported other audio at the start, or the tester documented why that public hint was unavailable despite clearly audible playback.
- Microphone capture started and stopped on command.
- Playback did not pause or become inaudible.
- Playback did not change to an unintended route.
- Any level change was small enough to meet the project's intended listening experience and was explicitly recorded.
- The app did not crash, hang, or falsely report another application's title/playback state.

Mark it **FAIL** if capture activation reproducibly pauses/silences playback, forces an unacceptable route, cannot stop, or crashes the app. Treat one transient network/Shazam/LRCLIB error as a separate service result unless it also prevents the audio-session observations.

Treat the run as **inconclusive** and repeat it when playback was not active at the start, the output could not be heard, the test was interrupted, an accessory changed during the run, or the observation was ambiguous. In the session template, explain the inconclusive result under **ACTUAL RESULT** and leave **PASS / FAIL** blank until the run is repeated.

## Recognition and lyrics interpretation

After coexistence is characterized, evaluate the downstream stages independently:

| Stage | Positive evidence | A negative result may mean |
| --- | --- | --- |
| Phone capture | `Microphone capture: Running`, a valid input route/sample rate/channel count, then `Stopped` | permission denial, unavailable input, session activation failure, interruption |
| ShazamKit | `Recognition state: Matched`, timestamp, latency, title and artist | music not audible to the selected input, silence/noise, unsupported catalog item, network/service error |
| LRCLIB | candidates returned and a conservative synchronized match selected | no provider record, plain-only/instrumental record, ambiguous metadata, network/HTTP/decoding error |
| Timeline | Playing state, monotonic elapsed time, lyric index/position advancing | no synchronized candidate, manual selection needed, pipeline error |

Apple specifically identifies silent input as a common cause of a Shazam invalid-signature error: [`SHError.signatureInvalid`](https://developer.apple.com/documentation/shazamkit/sherror/signatureinvalid). Headphone-only playback can be perfectly audible to the listener while remaining effectively silent to the phone microphone.

## Route matrix

Run the built-in-speaker case first. Then repeat only the route cases relevant to the intended use. Fully stop recognition before attaching or removing an accessory.

| Case | YouTube Music output before test | Expected input before test | What must be measured |
| --- | --- | --- | --- |
| Primary | Built-in speaker | Built-in microphone | continuation, level, feedback, route before/during/after, Shazam result |
| Wired accessory | Wired headphones or audio adapter | iOS-selected input | whether `.defaultToSpeaker` overrides the accessory; selected input; whether music remains audible to that input |
| Bluetooth A2DP | Bluetooth headphones/speaker | iOS-selected input | profile/route changes, quality changes, output rerouting, selected input, Shazam result |
| USB audio | USB output or interface | iOS-selected input | input/output ports, sample rate/channels, route changes, continuation |
| AirPlay/cast | AirPlay or cast destination | iOS-selected input | whether the route remains active, whether capture activates, whether the phone mic can hear the remote speaker |

Do not prescribe a successful accessory result. Apple documents route changes as occurring when audio devices are added or removed and provides `currentRoute`/route-change notifications for observation: [Responding to audio route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes). This project records those public facts; the human tester records what was actually audible.

If music plays from a second phone or independent speaker, label the result **external-source recognition**, not same-iPhone YouTube Music coexistence. It is a supported fallback for recognition but does not answer the primary experiment.

## Pause, seek, and synchronization test

Rokid Lyrics cannot observe later actions in YouTube Music. Test this limitation explicitly after obtaining a synchronized timeline:

1. Let the active lyric line advance for at least 15 seconds.
2. In YouTube Music, pause playback for 5 seconds, then resume.
3. Return to Rokid Lyrics.
4. Observe that the independent lyric clock did not receive a private pause event from YouTube Music.
5. Correct it with **SYNC**, `-1`/`+1`, `-5`/`+5`, or previous/next lyric.
6. Repeat with one deliberate seek in YouTube Music.
7. Record the pre-correction drift, applied correction, and post-correction result without copying lyric text.

This expected need for manual correction is not a bug in cross-app playback-state reading; such reading is outside the supported architecture. The initial Shazam match offset is only an estimate, and later source-player actions remain unobservable.

## Interruption and route-change test

Apple describes calls and other system events as normal audio-session interruptions and provides interruption notifications for apps to observe: [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions). Run only a safe, controlled interruption—never while driving or relying on the phone for an urgent call.

1. Start the coexistence action.
2. Trigger one controlled interruption appropriate to the test device.
3. End the interruption.
4. Record YouTube Music's behavior, the app's microphone state, **Last interruption**, and the audio notification log.
5. Do not assume automatic resume. If needed, explicitly stop and restart the test.
6. Repeat separately with one accessory connection/disconnection if that route matters.

## Foreground, app-switching, and screen-lock limits

The main supported recognition run keeps Rokid Lyrics in the foreground after switching away from YouTube Music. Test background behavior separately; do not fold it into the primary pass.

The app does not declare the `audio` background mode. Its optional `bluetooth-central` declaration is a different value and does not promise arbitrary microphone capture, timers, Shazam work, or display updates while suspended. Apple lists these as distinct background modes in [`UIBackgroundModes`](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes). Apple's `.playAndRecord` documentation also says an app needs the `audio` background mode to continue its own audio when it moves to the background: [`playAndRecord`](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord).

Run and record these transitions separately:

1. Start lyrics and wait for a timeline.
2. Switch to YouTube Music for 15 seconds.
3. Return and record whether capture, UI updates, and timeline state remained coherent.
4. Repeat with the iPhone locked for 15 seconds.
5. Repeat after a route change.

Acceptable behavior for the current MVP is honest, coherent recovery without a crash or fabricated continuous-update claim. Continuous background capture or glasses updates are not currently promised.

## Rokid glasses microphone variant

The proprietary Hardware build selects the Rokid glasses PCM adapter when the SDK is compiled, Mock Mode is off, authorization succeeds, and the official SDK provides a stream. That path does not configure the phone's `AVAudioSession` in current project code.

Do not infer that this improves coexistence. It has a different input path and remains unverified until a linked, signed Hardware build and physical glasses produce recorded PCM evidence. Use **Settings → Developer Diagnostics → Rokid Hardware Test** to isolate connection, synthetic display, Unicode, and glasses-microphone checks before attempting full recognition. Report it as a separate test configuration.

## Share-sheet and manual fallbacks

If acoustic coexistence or recognition is unreliable:

1. In YouTube Music, choose **Menu → Share**. Google documents this supported action and the option to copy a link: [Share music & podcasts](https://support.google.com/youtubemusic/answer/9198182?hl=en).
2. Select **Share to Rokid Lyrics** in the standard iOS Share sheet.
3. Verify or enter both title and artist.
4. Treat a URL as a reference only. The extension does not fetch it, scrape it, or assume a stable host/path/query structure.
5. Save the confirmed draft.
6. Open Rokid Lyrics, search LRCLIB, select the appropriate synchronized result, and align it manually.

Apple documents that a Share extension receives the text and attachments the host places in its `NSExtensionContext`: [App Extension Programming Guide — Share](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html). The exact items supplied by a particular YouTube Music build, locale, account, or shared-item type are empirical data. If title or artist is missing, require confirmation rather than guessing.

The simplest fallback is **Find Lyrics**: enter title and artist manually, select a synchronized LRCLIB result, then use the sync controls. Neither fallback supplies a trustworthy elapsed playback position.

## Privacy and evidence handling

- Start microphone capture only for an intentional test.
- Stop immediately if private speech enters the environment.
- Do not save or attach raw audio.
- Do not store real lyric text in a test report, screenshot, fixture, or issue.
- Prefer the sanitized diagnostics report over screenshots.
- Review even sanitized output before sharing; track title, artist, public provider identifiers, a sanitized catalog URL, timing, and a marker that local notes were omitted may remain. The note text itself is not copied.
- Never attach an SDK authorization callback, token, credential, certificate, provisioning profile, device UDID, full SDK log, or personal filesystem path.
- Record failures as failures or inconclusive results. Do not translate an expected-result description into evidence that it occurred.

## Official sources

- Apple: [`MPNowPlayingInfoCenter`](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- Apple: [Generating a signature from an audio buffer](https://developer.apple.com/documentation/shazamkit/generating-a-signature-from-an-audio-buffer)
- Apple: [`SHSession`](https://developer.apple.com/documentation/shazamkit/shsession/)
- Apple: [`SHError.signatureInvalid`](https://developer.apple.com/documentation/shazamkit/sherror/signatureinvalid)
- Apple: [`AVAudioApplication`](https://developer.apple.com/documentation/avfaudio/avaudioapplication)
- Apple: [`AVAudioSession.playAndRecord`](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord)
- Apple: [`AVAudioSession.CategoryOptions.mixWithOthers`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers)
- Apple: [`AVAudioSession.CategoryOptions.defaultToSpeaker`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/defaulttospeaker)
- Apple: [Responding to audio route changes](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes)
- Apple: [Handling audio interruptions](https://developer.apple.com/documentation/avfaudio/handling-audio-interruptions)
- Apple: [`UIBackgroundModes`](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes)
- Apple: [App Extension Programming Guide — Share](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)
- Google: [Explore YouTube Music Premium benefits](https://support.google.com/youtubemusic/answer/9266556?hl=en)
- Google: [Share music & podcasts](https://support.google.com/youtubemusic/answer/9198182?hl=en)
