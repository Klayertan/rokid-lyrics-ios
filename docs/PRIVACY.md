# Privacy

Rokid Lyrics processes microphone audio and song metadata, so listening must always be explicit and visible. The project does not use advertising SDKs, analytics SDKs, trackers, private YouTube APIs, or a raw-audio recorder.

This document describes the repository implementation as of 2026-08-11. A distributor must review the final binary, enabled SDKs, server policies, App Store privacy disclosures, and jurisdiction-specific requirements before release.

## Microphone behavior

Microphone access begins only after the user presses **Start Lyrics** and iOS permission has been granted. The app's usage description is:

> Rokid Lyrics listens briefly through the iPhone microphone to identify music and never stores the captured audio.

While capture is active, the app model exposes `isMicrophoneActive` and the UI shows a red microphone/listening status. Capture stops after a match attempt, error, explicit Stop, stream termination, or task cancellation.

`PhoneMicrophoneAudioCaptureService` copies normalized PCM frames into an in-memory `AsyncThrowingStream` with a bounded newest-frame buffer. It does not create an audio file, send raw PCM through the project's networking client, or persist frames to `UserDefaults` or a cache.

Conditional source for `RokidMicrophoneAudioCaptureService` exists only behind `ROKID_SDK_AVAILABLE && canImport(RGCxrClient)`. It converts the SDK's verified PCM stream to the same in-memory frame model and requests the SDK microphone authorization scope. It is not enabled in the public/mock build and has not been exercised on glasses, so capture quality, permission UI, transport security, SDK-side processing, and device behavior are not claimed. If enabled, the same visible-listening and no-project-persistence requirements apply.

The identification service converts those frames to a Shazam acoustic signature and gives the signature to Apple's ShazamKit matching API. Apple describes the signature as much smaller than the audio and one-way, so it cannot be converted back to the recording: [ShazamKit overview](https://developer.apple.com/documentation/shazamkit). The project does not control Apple's processing or retention; users and distributors should review Apple's current terms and privacy information.

The current app declares only `bluetooth-central` in `UIBackgroundModes` for the optional device-connection path; it does not declare the `audio` background mode and does not claim silent background recording. See the platform limitation discussion in [`YOUTUBE_MUSIC_LIMITATIONS.md`](YOUTUBE_MUSIC_LIMITATIONS.md).

## Data inventory

| Data | Source | Purpose | Destination/storage | Retention in this implementation |
| --- | --- | --- | --- | --- |
| Microphone PCM | Selected iOS input route; optional verified-SDK glasses stream when explicitly built/configured | Build a Shazam signature | Process memory only in project code | Capture session only |
| Shazam signature | Derived on device from PCM | Catalog matching | Passed to ShazamKit | Not persisted by project code |
| Track title, artist, IDs, artwork URL, match offsets, optional confidence | ShazamKit | Lyrics search, timing, UI, diagnostics | Memory; some identifiers used in local correction/cache keys | Session, except keys/cache described below |
| Lyrics query metadata | Identified track or user input | LRCLIB search | HTTPS URL query to `lrclib.net` | Server handling is outside this project |
| Plain/synchronized lyric candidates | LRCLIB | Candidate selection and display | Memory and bounded app Caches storage | Up to 30 days and 100 cache entries in the default app composition |
| Per-track sync correction | User controls | Restore manual timing | Standard `UserDefaults` | Until reset/uninstall; current UI has no per-track delete action |
| App settings | User | Presentation and behavior | Standard `UserDefaults` | Until reset/uninstall |
| Shared title, artist, URL, and raw shared text | Share host and user confirmation | Transfer one draft to the main app | App Group `UserDefaults` | Until consumed/replaced or app data is removed |
| Optional artwork image | URL supplied by ShazamKit | Phone UI | Fetched at display time by `AsyncImage`; normal system/network caching behavior may apply | Controlled by platform URL loading/cache behavior, not the lyrics cache |
| Diagnostic JSON | Derived app state | User-directed troubleshooting | On screen; clipboard only when the user taps Copy | Clipboard/system controlled after copy |

The LRCLIB cache contains copyrighted runtime lyrics in ordinary JSON files protected by the app sandbox; its filename hash is for safe naming, not encryption. Cache failures are ignored, and the operating system may purge the Caches directory.

## Network requests

### ShazamKit

The app supplies a generated signature to `SHSession` for matching. The project does not send raw PCM with `URLSession`. Returned metadata can include title, artist, identifiers, artwork URL, match offsets, and confidence on supported OS versions.

### LRCLIB

The app sends an HTTPS `GET /api/search` request containing:

- track title;
- artist;
- album, when available;
- an identifying `User-Agent` with the open-source project URL.

These values are URL query parameters and may therefore appear in LRCLIB/server network logs. No LRCLIB API key or account is used. The official endpoint contract is documented at [LRCLIB API Documentation](https://lrclib.net/docs). This project cannot promise LRCLIB's availability, data accuracy, policies, or retention.

### Artwork

When ShazamKit returns an artwork URL and the phone UI displays it, `AsyncImage` may contact that URL's host. This is separate from LRCLIB and is not needed for lyric synchronization.

## Share extension

The share extension declares support for standard plain text and one web URL. It accepts only `http` and `https` URLs, never opens the URL, and does not scrape YouTube Music.

Before saving, the extension requires nonempty title and artist fields. It encodes one `SharedTrackDraft` in `UserDefaults(suiteName: "group.com.rokidlyrics.shared")`. Apple documents App Group suite use for sharing settings between an app and extension at [`UserDefaults.init(suiteName:)`](https://developer.apple.com/documentation/foundation/userdefaults/init%28suitename%3A%29).

The main app removes the stored value when it consumes the draft, including when decoding fails. If the user never returns to the main app, the last saved draft can remain until another draft replaces it or app data is deleted.

## Local persistence details

### Lyrics cache

The default disk cache is stored under the app's Caches directory. Each entry includes the time stored and complete LRCLIB candidate objects. An entry expires after 30 days on its next read. After a write, files beyond the 100-entry limit are pruned oldest-first by modification date.

There is currently no in-app cache browser or Clear Cache control. Deleting—not merely offloading—the app removes its sandbox and App Group data subject to normal iOS behavior. A release-quality settings screen should add narrowly scoped deletion actions before claiming user-controlled erasure.

### Corrections and settings

Manual lyric corrections are stored by track ID in standard `UserDefaults`. When ShazamKit supplies no catalog ID, the fallback ID can include title and artist text. Settings include line count, font scale, automatic reconnect, default offset, mock mode, line visibility, vertical position, recognition behavior, and placeholder translation/transliteration choices.

### No secret storage

No API key, Apple credential, Rokid credential, certificate, provisioning profile, or authorization token belongs in source control or diagnostic output. `.gitignore` excludes common signing material, local configuration, and expected proprietary SDK directories.

If a proprietary Rokid adapter is enabled, its authentication and logging behavior must be reviewed separately. Do not enable SDK logging that can persist callback URLs or tokens; follow the verified cautions in [`ROKID_SDK_NOTES.md`](ROKID_SDK_NOTES.md).

The conditional coordinator forwards the registered `cxrl` callback URL directly to the SDK's verified handler and does not log or store the URL in project code. Authentication callback URLs must be treated as credentials: never add them to diagnostics, crash reports, screenshots, or issue attachments. The public/mock composition does not instantiate this coordinator.

## Diagnostics

Developer Diagnostics intentionally contains no raw PCM, API credentials, authorization tokens, signing identities, or full service requests. It can contain privacy-sensitive context:

- track ID, title, artist, and album;
- identification source and optional confidence;
- normalized song metadata;
- lyric-provider result summary;
- current playback/timeline position and offset;
- the previous/current/next lyric text in the last display payload;
- connection and recognition state;
- recent error text.

The app copies diagnostics only after a user taps Copy. Users should review the JSON before sharing because metadata and lyric fragments may reveal listening activity. Future adapters must redact secrets at their boundary before adding fields.

## Data the project does not request

The current code does not request or intentionally collect:

- contacts;
- location;
- photos or media library access;
- YouTube/Google account credentials;
- another app's queue or playback history;
- advertising identifiers;
- analytics events;
- continuous raw-audio recordings.

## Operational privacy checklist

Before a public TestFlight or App Store build:

- verify the microphone indicator and Stop behavior on a physical device;
- test every success, failure, cancellation, interruption, and background transition for prompt capture shutdown;
- inspect the app container to confirm no raw audio files are created;
- packet-inspect a development build to verify expected ShazamKit, LRCLIB, and artwork destinations only;
- add user-facing Clear Lyrics Cache and Clear Corrections controls if required for release;
- confirm App Group identifiers and production bundle IDs are correct;
- review Apple privacy manifests/disclosures for the final dependency set;
- review LRCLIB and Rokid policies for the intended distribution;
- confirm diagnostics redact any future credentials or SDK logs;
- never include real lyrics or private account information in bug reports, screenshots, fixtures, or repository history.
