# YouTube Music and iOS limitations

## Supported integration model

Rokid Lyrics does not integrate with YouTube Music as a data service or player controller. It treats YouTube Music exactly like any other app producing sound:

```text
audible music -> supported microphone input -> ShazamKit identity -> LRCLIB lyrics
```

There is also a user-initiated fallback:

```text
YouTube Music Share -> standard iOS share items -> confirm title/artist -> manual lyrics search
```

This design uses public Apple extension, audio, and ShazamKit APIs. It does not use a private YouTube Music API, scrape a shared page, reverse-engineer the YouTube Music app, or import a private iOS framework.

## Playback state is not available to this app

Rokid Lyrics has no supported way to ask another iOS app for its private queue, exact elapsed time, pause/seek events, or decoded audio buffer.

`MPNowPlayingInfoCenter` is not used as a cross-app reader. Apple documents it as an object for setting Now Playing information for media that **your app plays**, so this project does not interpret the API as permission or a contract to inspect YouTube Music: [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter).

Consequences:

- Identification is one-shot acoustic recognition, not a subscription to YouTube Music state.
- The initial lyric position is an estimate from ShazamKit's documented [`predictedCurrentMatchOffset`](https://developer.apple.com/documentation/shazamkit/shmatchedmediaitem/predictedcurrentmatchoffset).
- If the user pauses, seeks, changes playback speed, changes track, or encounters an advertisement in YouTube Music, Rokid Lyrics is not notified.
- The lyric clock continues independently until the user pauses, resynchronizes, changes the selected lyrics, or stops the session.
- Manual `-5`, `-1`, `Sync`, `+1`, `+5`, previous-line, and next-line controls exist because drift and imperfect initial alignment are expected.
- A future `AudioAlignmentService` may improve estimates through a supported audio path, but no speculative implementation is included.

When ShazamKit supplies a predicted position, the current orchestration starts its monotonic clock as soon as identification completes, so LRCLIB lookup and parsing time are included before lyrics appear. This removes one deterministic source of lateness, but it cannot compensate for acoustic/route latency or any later source-player change.

## Microphone capture and concurrent music

The current `PhoneMicrophoneAudioCaptureService`:

- requests microphone permission;
- configures `AVAudioSession` as `.playAndRecord` in `.default` mode;
- requests `.mixWithOthers` so another app's audio can continue;
- requests `.defaultToSpeaker`;
- captures input through an `AVAudioEngine` tap;
- keeps up to 32 recent PCM frames in memory;
- stops capture after identification, failure, or cancellation;
- does not intentionally write raw audio to disk.

Apple says `.playAndRecord` supports simultaneous input and output and that `.mixWithOthers` allows the session to mix with audio from background apps. See [`playAndRecord`](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord) and [`mixWithOthers`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/mixwithothers). Apple describes `.defaultToSpeaker` as changing the default route from the receiver to the built-in speaker: [`defaultToSpeaker`](https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/defaulttospeaker).

Those documented category semantics are not a substitute for a device experiment. As of 2026-08-12, this repository has **not** verified on a physical iPhone whether activating this exact session while YouTube Music is playing:

- keeps playback running;
- pauses or ducks it;
- moves it between speaker, receiver, wired, Bluetooth, USB, or AirPlay routes;
- selects the built-in microphone or an accessory microphone;
- supplies audio with enough quality for ShazamKit;
- behaves consistently across current iPhone and iOS versions.

The **Physical iPhone Tests** screen records the public session category/mode/options, route port types, selected input type, sample rate/channels, other-audio flags, route-change/interruption notifications, and microphone state. It also lets the human tester record whether playback continued, ducked, paused, rerouted, or became inaudible. Those controls collect observations; they cannot determine audible quality automatically. The app does not explicitly select a preferred microphone and does not yet implement full route-change/interruption recovery.

Most importantly, the input tap captures the selected microphone/input route; it is not a digital tap into YouTube Music. If music is playing only in headphones, the phone microphone may not hear it. Speaker playback may be acoustically available to the microphone, but recognition quality and echo/routing behavior remain physical-device test items.

An SDK-enabled non-mock build conditionally uses the verified CXR-L PCM media interface through `RokidMicrophoneAudioCaptureService` instead of `AVAudioEngine`. That source is included in the target-mode app that linked and embedded the genuine `RGCxrClient`/`RGCoreKit`/`CocoaLumberjack` dependency graph. The validation app was unsigned, unlaunched, and built with the asset catalog excluded only to bypass the local `actool` failure; the ordinary hardware workspace build remains blocked by the missing iOS 26.5 platform. The source still supplies ambient microphone audio—not YouTube Music state or a digital player tap—and its effect on YouTube Music playback, Bluetooth routing, background behavior, and recognition quality is entirely untested.

Use [`YOUTUBE_MUSIC_DEVICE_TEST.md`](YOUTUBE_MUSIC_DEVICE_TEST.md) for the controlled same-iPhone experiment and a fresh copy of [`DEVICE_TEST_SESSION.md`](DEVICE_TEST_SESSION.md) to record each run. A compile, link, diagnostic label, or expected-result paragraph is never evidence that coexistence succeeded.

## Foreground and background behavior

The application `Info.plist` currently declares `bluetooth-central` for the optional device-connection path, but it does **not** declare the `audio` background mode. The supported recognition MVP is therefore foreground use. The Bluetooth declaration does not authorize or prove continuous microphone capture, network lookup, lyric advancement, or transport updates after iOS suspends the app.

Apple notes that background audio capability requires the appropriate background-mode declaration; see [`UIBackgroundModes`](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes) and the background discussion in [`playAndRecord`](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playandrecord).

Practical implications:

- Start recognition while Rokid Lyrics is visible and music is already audible.
- Do not assume recognition continues if the user switches away or locks the phone.
- Do not assume a long-running lyric session stays active under screen lock, memory pressure, calls, Siri, alarms, or audio-route changes.
- Background modes should not be added merely to bypass normal suspension. Any future use must match an Apple-supported background purpose and be tested for App Store compatibility, battery cost, and privacy behavior.

## What the YouTube Music share sheet provides

Google's public help page says YouTube Music can share a song, album, playlist, or podcast and can copy a link: [Share music & podcasts](https://support.google.com/youtubemusic/answer/9198182?hl=en). It does **not** document a stable iOS `NSItemProvider` contract that guarantees separate track-title and artist fields.

Apple's Share extension contract likewise gives the extension the representations supplied by the host through `NSExtensionContext`; it does not promise music-specific metadata: [App Extension Programming Guide: Share](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html).

The implemented extension therefore accepts only standard plain text and at most one standard web URL. Its parser:

- keeps only `http` or `https` URLs;
- does not require or interpret a YouTube hostname;
- accepts two clean non-URL text lines as a possible title and artist;
- accepts one line split by a single spaced hyphen/en dash/em dash as a possible pair;
- preserves CJK text;
- treats URL-only input as insufficient;
- requires user confirmation for all conservatively parsed data;
- never fetches or scrapes the shared URL.

The user must complete both title and artist before saving. The extension stores one pending draft in the shared App Group; the main app consumes it into the manual-search screen when active.

### Experimental status

The parser has unit tests for standard text/URL shapes, including URL-only and CJK cases. The actual items emitted by a current YouTube Music iOS build have **not** been captured on a physical device in this project. No particular URL host, path, query parameter, ordering, separator, or text layout is claimed stable.

The hardware test should record, without publishing private account data:

1. iOS version and YouTube Music version;
2. whether the host supplies `attributedContentText`;
3. each attachment's registered type identifiers;
4. whether the loaded item is `URL`, `String`, or attributed text;
5. song, video, album, playlist, podcast, and timestamp-share differences;
6. locale-dependent differences;
7. whether the user-confirmation UI behaves safely for incomplete data.

Tests should inform parser fixtures, but the app must continue to confirm uncertain metadata rather than lock onto an undocumented format.

The device-diagnostics screen also provides an explicit **LIVE LRCLIB TEST** after the tester enters title and artist. It bypasses the app's normal lyrics cache for that request and reports candidate metadata, match scores, and synchronized/plain/instrumental availability without displaying or copying lyric bodies. It never runs automatically or in CI, and no successful live request has yet been recorded.

## Supported fallback workflows

1. **Acoustic recognition:** Leave music playing audibly, keep Rokid Lyrics in the foreground, and press Start Lyrics. This path still needs physical-device coexistence testing.
2. **Share then confirm:** Share from YouTube Music to Rokid Lyrics, verify title and artist in the extension, return to the main app, and choose an LRCLIB result. This avoids microphone recognition but does not provide a trustworthy playback position.
3. **Manual search:** Type title and artist directly and choose the matching LRCLIB candidate. This also begins without source-player timing, so manual line/sync controls are required.

None of these workflows grants control over YouTube Music or guarantees that a lyric record exists, is synchronized, is the correct version, or remains aligned after source-player changes.
