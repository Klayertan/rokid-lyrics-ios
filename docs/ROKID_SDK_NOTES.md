# Rokid CXR-L iOS SDK notes

Last verified: 2026-08-12

## Status and evidence boundary

The repository has an optional, strongly isolated adapter for Rokid's real iOS SDK. The runtime selects it only when the app was compiled with `ROKID_SDK_AVAILABLE`, `RGCxrClient` can be imported, and the user turns off Mock Mode; otherwise it uses `MockRokidDisplayTransport` and the phone-microphone capture service.

On 2026-08-12 the application sources at this validation milestone were compiled and linked as an unsigned arm64 iPhoneOS application against the genuine CocoaPods dependency graph: `RGCxrClient` 1.0.4, `RGCoreKit` 0.0.2, and `CocoaLumberjack` 3.9.1. CocoaPods embedded all three real frameworks and the resulting app executable records all three in its Mach-O load commands. This was a target-mode validation build with `Assets.xcassets` excluded solely because this Mac has no installed iOS runtime for `actool`; the normal workspace/scheme build could not start because Xcode marked the generic iOS destination ineligible. The build was **not** code-signed, installed, launched, authorized, connected to glasses, or hardware-tested. Those distinctions are intentional and are detailed under [Compilation and link evidence](#compilation-and-link-evidence).

The findings in this document come from these official artifacts:

- Rokid's public CocoaPods spec for [`RGCxrClient` 1.0.4](https://cdn.cocoapods.org/Specs/b/d/c/RGCxrClient/1.0.4/RGCxrClient.podspec.json).
- CocoaPods Trunk's live [`RGCxrClient` metadata](https://trunk.cocoapods.org/api/v1/pods/RGCxrClient) and [`RGCoreKit` metadata](https://trunk.cocoapods.org/api/v1/pods/RGCoreKit).
- The framework archive linked by that spec: [`RGCxrClient_1.0.4.2.framework.zip`](https://rokid-ota.oss-cn-hangzhou.aliyuncs.com/toB/Rokid_Glass/SDK/CXR-L%28iOS%29/release/RGCxrClient_1.0.4.2.framework.zip).
- Rokid's official [`ios_cxr_l_sample.zip`](https://rokid-ota.oss-cn-hangzhou.aliyuncs.com/toB/Document/CXR-L/v1.0.4/iOS/ios_cxr_l_sample.zip), including its `Podfile`, `Podfile.lock`, `CXRClientDemo`, `modules/RGCxr/RGCxrClient/API.md`, public Swift declarations, and implementation sources.
- Rokid's [developer community agreement](https://developer.rokid.com/docs/4-TermsAndAgreements/community-service-agreement.html).

Local paths shown below identify the exact extracted research artifacts used for verification. They are deliberately outside the repository and are not installation paths:

- Framework: `/tmp/rgcxr-framework.oYS60a/RGCxrClient.framework`
- Public interface: `/tmp/rgcxr-framework.oYS60a/RGCxrClient.framework/Modules/RGCxrClient.swiftmodule/arm64-apple-ios.swiftinterface`
- Official sample: `/private/tmp/ios-cxr-l-inspect.Kp5mZR`

## Package, version, and platform

| Item | Verified value | Evidence |
| --- | --- | --- |
| Public pod version | `RGCxrClient` 1.0.4 | Public CocoaPods spec linked above |
| Distributed archive revision | Filename `RGCxrClient_1.0.4.2.framework.zip` | Public CocoaPods spec `source.http` |
| Official sample resolution | `RGCxrClient (1.0.4.2)` | Official sample `Podfile` and `Podfile.lock` |
| Framework bundle version | `CFBundleShortVersionString = 1.0.4` | Framework `Info.plist` |
| Required dependency | `RGCoreKit = 0.0.2` | Public RGCxrClient spec and official sample `Podfile.lock`; see the public [`RGCoreKit` 0.0.2 spec](https://cdn.cocoapods.org/Specs/6/e/9/RGCoreKit/0.0.2/RGCoreKit.podspec.json) |
| Resolved logging dependency | `CocoaLumberjack/Swift` 3.9.1 | `RGCoreKit` spec declares `CocoaLumberjack/Swift`; the 2026-08-12 generated `Podfile.lock` and official sample lockfile resolve 3.9.1 |
| Framework architecture | arm64 iPhoneOS only; no simulator slice | Framework Mach-O and `Modules/RGCxrClient.swiftmodule/arm64-apple-ios.*` |
| Binary minimum OS | iOS 16.0 | Framework `Info.plist` `MinimumOSVersion` and Swift interface target `arm64-apple-ios16.0` |
| Binary build tool | Xcode 26.5 / iPhoneOS 26.5 SDK | Framework `Info.plist`: `DTXcode=2650`, `DTSDKName=iphoneos26.5` |

As observed through the live CocoaPods Trunk endpoints on 2026-08-12, `RGCxrClient` has published versions 1.0.1 and 1.0.4, with 1.0.4 current; `RGCoreKit` has versions 0.0.1 and 0.0.2, with 0.0.2 current. [Sources: CocoaPods Trunk [`RGCxrClient`](https://trunk.cocoapods.org/api/v1/pods/RGCxrClient) and [`RGCoreKit`](https://trunk.cocoapods.org/api/v1/pods/RGCoreKit) metadata.]

The public RGCoreKit 0.0.2 podspec obtains its sources from [`gingerjin93/RGCoreKit`](https://github.com/gingerjin93/RGCoreKit) at tag 0.0.2; that tag resolved to commit `65916682436df5e3b512b0e7d67d3d7ca7f573b6` during this verification. Its CocoaLumberjack/Swift dependency has no version constraint in the podspec, so the exact 3.9.1 version above is the lockfile result for this validation rather than a version promised by RGCoreKit. [Source: public [`RGCoreKit` 0.0.2 podspec](https://cdn.cocoapods.org/Specs/6/e/9/RGCoreKit/0.0.2/RGCoreKit.podspec.json); resolved Git tag and generated validation lockfile.]

`RGCxrClient` is not a self-contained framework. Its public Swift interface explicitly imports `RGCoreKit`, and `otool -L RGCxrClient.framework/RGCxrClient` records `@rpath/RGCoreKit.framework/RGCoreKit`. A consuming application must therefore compile and embed the genuine RGCoreKit dependency as well as the RGCxrClient binary; a placeholder Swift module is not sufficient to produce a valid runtime link. [Sources: distributed framework `arm64-apple-ios.swiftinterface`; distributed framework Mach-O load commands; public RGCxrClient podspec dependency declaration.]

There is a packaging inconsistency worth preserving: the public pod is called 1.0.4, its downloaded filename contains 1.0.4.2, and the sample lockfile resolves 1.0.4.2, while the bundled source-tree `modules/RGCxr/RGCxrClient.podspec` is stale at 1.0.3. This project therefore identifies the tested artifact as **public pod 1.0.4 / archive revision 1.0.4.2**, rather than pretending these version fields are identical. [Sources: public podspec; official sample `Podfile.lock`; official sample `modules/RGCxr/RGCxrClient.podspec`; framework `Info.plist`.]

For reproducibility, the downloaded files inspected on 2026-08-11 had these hashes:

```text
3dd722e595d0b94321453ec989dc1bd90813bb4080aef598e01e4aa3c2e1a243  RGCxrClient_1.0.4.2.framework.zip
3d71b3aaded934fcc20403e7651c73c1916e72826609568e757b76284082052b  ios_cxr_l_sample.zip
```

These hashes record what was inspected; Rokid could replace a file served at the same URL later.

The live CocoaPods JSON specs cached on 2026-08-12 had these hashes:

```text
b684553fe689e4d03572a0a75d1803a219345bf2771e9503bcf888191d043f64  RGCxrClient/1.0.4/RGCxrClient.podspec.json
47ba8e444a3dccbab866b034c7a614fb31eecd91ecd96b02bc736d06b1c00a5f  RGCoreKit/0.0.2/RGCoreKit.podspec.json
```

### Deployment target discrepancy

The podspec advertises iOS 13.0, and the sample documentation says iOS 13+, but the distributed framework itself has a minimum of iOS 16.0. The binary is authoritative for a consuming build. This project targets iOS 17. [Sources: public podspec `platforms`; official sample `modules/RGCxr/RGCxrClient/API.md`, “环境要求”; framework `Info.plist` and Swift interface header.]

## Installation

The verified public installation route is CocoaPods:

```ruby
platform :ios, '17.0'

target 'RokidLyrics' do
  use_frameworks!
  pod 'RGCxrClient', '1.0.4'
end
```

Then run `pod install` and open the generated workspace. `RGCoreKit 0.0.2` is a declared transitive dependency; it in turn declares `CocoaLumberjack/Swift`. [Sources: public `RGCxrClient` and `RGCoreKit` podspecs.]

`Config/Podfile.hardware.example` maps the repository's normal, Mock, and Rokid Hardware configurations. `Config/AppRokidHardwareDebug.xcconfig` and `Config/AppRokidHardwareRelease.xcconfig` contain optional includes for CocoaPods' matching generated app-target settings. This preserves the repository's custom base configuration without leaking the device-only SDK into the Share Extension. Regenerate the project first, copy the example to a local `Podfile`, run `pod install`, and open `RokidLyrics.xcworkspace`. [Sources: repository configuration files; CocoaPods-generated target support files from the 2026-08-12 validation.]

Do not copy the framework into this repository. Enable the adapter only for an iPhoneOS configuration that both links the locally installed pod and defines `ROKID_SDK_AVAILABLE` in `SWIFT_ACTIVE_COMPILATION_CONDITIONS`. The code is additionally guarded with `canImport(RGCxrClient)`, so mock builds remain independent of the proprietary artifact.

The framework has no simulator slice. Simulator and public CI jobs must continue to compile without `ROKID_SDK_AVAILABLE` and use the mock transport. [Source: distributed framework architecture and module contents.]

## Required app configuration

Rokid's sample and integration guide specify:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLName</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER).cxrl</string>
    <key>CFBundleURLSchemes</key>
    <array><string>cxrl</string></array>
  </dict>
</array>

<key>LSApplicationQueriesSchemes</key>
<array><string>rokidai</string></array>

<key>NSBluetoothAlwaysUsageDescription</key>
<string>Explain why the app connects to Rokid Glasses.</string>

<key>UIBackgroundModes</key>
<array><string>bluetooth-central</string></array>
```

[Sources: official sample `CXRClientDemo/Info.plist`; official sample `modules/RGCxr/RGCxrClient/API.md`, “工程配置”.]

The callback defaults declared by `RGCxrClientAuthConfig` are a request URL beginning `rokidai://connect` and callback `cxrl://auth/callback`. The app must forward every received candidate URL to the same `RGCxrLink.handleOpenURL(_:)` instance used for authorization. The adapter exposes `handleOpenURL(_:)` for a SwiftUI `onOpenURL` or equivalent scene/application callback and never logs or retains the URL. [Sources: framework Swift interface `RGCxrClientAuthConfig`; official sample `modules/RGCxr/RGCxrClient/API.md`, “URL 处理”.]

`NSMicrophoneUsageDescription` is still required for the separate iPhone microphone implementation. The verified Rokid-microphone path does not invoke Apple's microphone API; authorization for that path is the SDK's `.microphone` scope. [Sources: framework Swift interface `RGCxrClientAuthPermission`; official sample `RGCxrClient/API.md` media documentation; repository `PhoneMicrophoneAudioCaptureService`.]

## Initialization and authorization

The official sample initializes the SDK before using it:

```swift
let outcome = CxrClient.initialize(
    mode: .customView,
    options: .init(appDisplayName: "Rokid Lyrics", pageName: nil)
)
```

The only declared outcomes are `.success` and `.failureAlreadyInitialized`. The adapter accepts an already initialized SDK only when `CxrClient.initializationMode == .customView`; a prior CustomApp initialization is rejected rather than allowed to fail later with `.modeMismatch`. [Sources: official sample `CXRClientDemo/AppDelegate.swift`; framework Swift interface `RGCxrClientInitializeOutcome`, `CxrClient.initialize`, and `CxrClient.initializationMode`.]

The recommended typed flow is:

```swift
let link = CxrClient.makeLink(appDisplayName: "Rokid Lyrics")
let session = link.makeCustomViewSession(aiInterceptMode: .allowWithPause)

link.authenticate(scopes: [.microphone]) { result in
    // Never log the returned token.
}
```

The SDK opens the Rokid AI app for authorization. Its callback can contain a token, session ID, granted scopes, expiration, and device name. On success, the SDK uses the returned device name to initiate BLE; there is no separate public `connect(token:)` or device-picker API on `RGCxrLink`. [Sources: official sample `modules/RGCxr/RGCxrClient/API.md`, “Link + Typed Session”; official sample `RGCxrClientAuthManager.swift` `handleAuthSuccess`; official sample `RGCxrClientImpl.swift` `setupAuthObserver`; framework Swift interface `RGCxrLink`.]

No app key, client secret, developer credential, or serial-number parameter appears in the public Link/auth interface or sample configuration. This does **not** establish that every device/account is eligible: authorization still depends on the installed Rokid AI app, its signed-in user/device state, and any Rokid-side program rules. No credentials belong in source control. [Sources: framework Swift interface `RGCxrLink.authenticate`; official sample auth implementation and `Info.plist`. The eligibility caution is an explicit unresolved item, not an SDK claim.]

## Connection lifecycle

`link.events.connectionStatePublisher` publishes a Boolean BLE connection state. `session.statePublisher` publishes `.available`, `.started`, `.paused`, or `.unavailable`, with optional reasons including `linkConnected`, `linkDisconnected`, `glassReady`, `screenOffGlass`, `aiStart`, and `scenesTakeover`. [Source: framework Swift interface `RGCxrLinkEvents`, `RGCxrSessionState`, and `RGCxrSessionStateReason`.]

The SDK's implementation marks BLE connected in `didConnect` before service/characteristic discovery finishes. It queues writes until both write and notify characteristics are ready. Consequently, the adapter treats the operation callback—not the first `true` connection event—as proof that an open/update command completed. [Source: official sample `modules/RGCxr/RGCxrClient/Classes/Project/RGCxrClientBLE.swift`, `handleConnectedPeripheral`, `isGattReady`, and `flushWriteQueueIfPossible`.]

The SDK implementation schedules automatic reconnects for unintended disconnects with bounded exponential delay up to 30 seconds. The adapter retains the most recent SDK-neutral display payload and re-opens it after the link reconnects; it does not emit per-frame updates. [Source for SDK behavior: official sample `RGCxrClientBLE.swift`, `scheduleReconnectIfNeeded`. Source for adapter behavior: `RokidCXRCoordinator.swift`.]

### Explicit disconnect caveat

In 1.0.4.2, `link.disconnect()` clears the BLE target name. A subsequent `authenticate` with an in-memory, unexpired token returns through a fast path without emitting `authenticationSucceeded`; that event is what ordinarily supplies the device name to `ble.connect(name:)`. The adapter therefore calls the public `CxrClient.shared.auth.clearAuthentication()` after an explicit disconnect so a later Connect action performs a fresh supported authorization flow. Transient drops are left to the SDK's auto-reconnect path. [Code-level finding from the official sample: `RGCxrClientBLE.swift` `disconnect`; `RGCxrClientAuthManager.swift` `authenticate`; `RGCxrClientImpl.swift` `setupAuthObserver`.]

## CustomView display API

The exact typed display calls verified in the framework are:

```swift
session.customView.setIcons(_:callback:)
session.customView.open(_:callback:)
session.customView.update(_:callback:)
session.customView.close(callback:)
session.customViewEvents.lifecyclePublisher
```

`open` and `update` accept JSON strings. The official sample represents a view tree as `{ "type", "props", "children" }` and update operations as an array of `{ "action": "update", "id", "props" }`. Its exercised node types are `LinearLayout`, `RelativeLayout`, `TextView`, and `ImageView`. Its exercised text/layout properties include stable `id`, `layout_width`, `layout_height`, `orientation`, `gravity`, margins, padding, `text`, `textColor`, `textSize`, and `textStyle`. [Sources: framework Swift interface `RGCxrSessionCustomView`; official sample `CXRClientDemo/CustomViewItems.swift` and `ViewController.swift` `createCustomViewWithStructs` / `createUpdateCustomViewData`.]

The repository encoder deliberately uses only `LinearLayout` plus `TextView`, a stable ID for each text node, and properties found in that sample. Lyrics updates send only text/font-size changes. It maps the abstract vertical-position setting to the verified `top`, `center_vertical`, or `bottom` gravity values; it does not invent coordinates. Because the sample does not demonstrate changing root gravity through `update`, the adapter applies a gravity change with the verified close/open lifecycle. JSON is generated with `Codable`, preserving Unicode and escaping rather than interpolating strings.

The official guide says large open/update text payloads use a temporary local TCP channel and time out at about 30 seconds; close remains on BLE with about a five-second timeout. No official maximum payload size, safe refresh frequency, frame rate, or text-length limit was found in the public interface, integration guide, or sample. The adapter deduplicates identical visible updates and sends only when content changes. [Sources: official sample `modules/RGCxr/RGCxrClient/API.md`, legacy API table; official sample `RGCxrClientImpl.swift`, `customViewPayloadClientTimeoutInterval` and callback registration. “Not found” records the research boundary.]

The sample passes UTF-8 Swift strings to the display API, but it does not document the glasses' installed fonts or guarantee Japanese, Chinese, or Korean glyph coverage. The encoder and tests preserve English, 日本語, 中文, and 한국어; actual glyph rendering remains a hardware test. No font-installation API was found in the verified public interface. [Sources: framework Swift interface; official sample CustomView model/API.]

## Glasses microphone audio

Glasses microphone access is verified. The typed API is:

```swift
session.media.startAudioStream(codec: .pcm, mode: .antClose)
session.media.stopAudioStream()
session.mediaEvents.audioPublisher
```

Audio events are `.started(RGCxrClientAudioStartEvent)` and `.stream(RGCxrClientAudioDataEvent)`. The start event exposes codec, type, and channel count; stream events expose `Data` and a `UInt64` timestamp. The timestamp unit is not documented, so the adapter does not guess: it assigns `ProcessInfo.processInfo.systemUptime` when each packet is received. [Source: framework Swift interface `RGCxrClientAudioEvent`, `RGCxrClientAudioStartEvent`, and `RGCxrClientAudioDataEvent`.]

The SDK declares codecs `.pcm`, `.oggOpus`, and `.mp3` and modes `.xf`, `.antClose`, `.rokidOmni`, `.antOmni`, `.xfOrientation`, and `.barrierFree`. Their acoustic meanings and selection guidance are not documented in the integration guide. This adapter uses `.antClose` solely because that is the mode exercised by Rokid's official iOS sample; it does not claim `.antClose` is objectively best for music recognition. [Sources: framework Swift interface `RGCxrAudioCodec` / `RGCxrAudioMode`; official sample `CXRClientDemo/ViewController.swift`, `startRecordTapped`.]

The sample wraps received PCM as 16 kHz, mono, signed 16-bit little-endian audio for playback. The adapter uses the documented event's channel count rather than forcing mono, decodes signed PCM16 little-endian samples to normalized floats, and uses 16 kHz. Partial sample frames are buffered in memory; raw audio is never written to disk. [Source: official sample `CXRClientDemo/ViewController.swift`, `packageWavHeader`; framework Swift interface start event `channels`.]

In CustomView mode the SDK requires a running CustomView before `startAudioStream`; paused/unavailable sessions reject media commands and pause stops active local streams. The audio service first opens a minimal “Listening for music…” display, waits for `.started`, then requests PCM. [Sources: official sample `RGCxrSessionImpl.swift`, `ensureSessionStarted` and `startAudioStream`; `RGCxrClientImpl.swift`, `ensureMediaPreconditions` and `stopActiveLocalStreamsForPause`.]

The SDK architecture document says received audio uses a temporary localhost TCP channel while BLE carries control/heartbeat traffic. The adapter itself does not configure `AVAudioSession`, so it does not intentionally pause, duck, or reroute YouTube Music. Whether glasses capture and long-running local TCP remain reliable while the app is backgrounded—and whether any device firmware behavior affects phone playback—must be measured on real hardware. [Source: official sample `modules/RGCxr/RGCxrClient_Architecture.md`, audio-transfer sections. The playback/background statements are explicit unverified test requirements.]

## Background behavior

Rokid's integration guide and sample enable `bluetooth-central`, which allows CoreBluetooth-related background handling under iOS rules. Neither the public interface nor sample establishes that iOS will keep arbitrary lyric timers, local TCP audio streaming, Shazam processing, or display-update work running indefinitely after suspension. Do not interpret the presence of `bluetooth-central` as a promise of continuous background execution. [Sources: official sample `CXRClientDemo/Info.plist`; `modules/RGCxr/RGCxrClient/API.md`, “蓝牙后台模式”. The limitation follows from the absence of a stronger SDK contract and must be validated against Apple's supported execution model.]

Required hardware tests include screen lock, app background/foreground, YouTube Music continuing playback, a 30+ minute session, disconnect/reconnect, and audio interruption. Until those tests run, background lyric advancement and glasses-microphone recognition are **not hardware verified**.

## Logging and sensitive data

The sample calls `RGLog.setup(false)` and logs incoming callback URLs. The SDK auth implementation also logs the callback URL, which contains the authorization token. `RGLog.setup` adds a file logger (including release configuration), and the shipped `RGLog.addSensitive` implementation is commented out and therefore does not register redactions. [Sources: official sample `CXRClientDemo/AppDelegate.swift` and `SceneDelegate.swift`; official sample `modules/RGCxr/RGCxrClient/Classes/Project/RGCxrClientAuthManager.swift`; official sample `modules/RGCoreKit/Classes/RGLog.swift`.]

This adapter never initializes `RGLog`, never logs callback URLs/tokens/session IDs/device names, discards SDK error strings at the boundary, and exposes only bounded redacted error categories. A host app that independently enables `RGLog` should treat this SDK-version logging behavior as a credential-exposure risk.

## Licensing and redistribution

The public `RGCxrClient` and `RGCoreKit` podspecs declare their license type as `Copyright`, not an open-source license. The inspected framework archive did not include a permissive redistribution license. Rokid's developer agreement says developers must follow interface-provider rules and describes ordinary authorization as development/testing authorization, with certification and a separate agreement required for commercial operation. [Sources: public podspecs; Rokid [developer community agreement](https://developer.rokid.com/docs/4-TermsAndAgreements/community-service-agreement.html), especially sections 3(2)–3(4).]

Accordingly:

- Do not commit or redistribute `RGCxrClient.framework`, Rokid sample/SDK source, credentials, tokens, certificates, or provisioning profiles.
- Install the SDK locally from Rokid's published CocoaPods/artifact route.
- Obtain written clarification from Rokid before redistributing its binary or shipping commercially.
- The repository's MIT license covers only code written for this repository, not Rokid's SDK or its dependencies.

This is a conservative engineering decision, not legal advice.

## Adapter mapping

The optional implementation uses these exact verified APIs:

| Domain operation | SDK call |
| --- | --- |
| Initialize | `CxrClient.initialize(mode:.customView, options:)` |
| Create link | `CxrClient.makeLink(appDisplayName:)` |
| Authorize | `link.authenticate(scopes:[.microphone], completion:)` |
| Route callback | `link.handleOpenURL(_:)` |
| Observe BLE | `link.events.connectionStatePublisher` |
| Create session | `link.makeCustomViewSession(aiInterceptMode:.allowWithPause)` |
| Observe session | `session.statePublisher` |
| Open display | `session.customView.open(_:callback:)` |
| Update display | `session.customView.update(_:callback:)` |
| Clear display | `session.customView.close(callback:)` |
| Start glasses PCM | `session.media.startAudioStream(codec:.pcm, mode:.antClose)` |
| Receive PCM | `session.mediaEvents.audioPublisher` |
| Stop glasses PCM | `session.media.stopAudioStream()` |
| Disconnect | `link.disconnect()` then `CxrClient.shared.auth.clearAuthentication()` for an explicit user disconnect |

No SDK type escapes `RokidCXRCoordinator`, `CXRLRokidDisplayTransport`, or `RokidMicrophoneAudioCaptureService`.

## Compilation and link evidence

### Toolchain and genuine dependency resolution

The 2026-08-12 validation used:

```text
macOS host: 27.0 (26A5378j)
Xcode: 26.6 (17F113)
iPhoneOS SDK: 26.5
Swift: 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
XcodeGen: 2.46.0
CocoaPods: 1.17.0
Ruby: 4.0.6
```

The latest test was performed in the fresh disposable copy `/tmp/rokid-genuine-current.7N6SKw`; no pod, workspace, framework, or build product was added to the repository. `xcodegen generate` created the project and `Config/Podfile.hardware.example` was copied to the temporary root as `Podfile`. Immediately before and after the build, recursive byte comparisons found no differences between the live workspace and the snapshot's `RokidLyrics`, `RokidLyricsShareExtension`, `Sources`, and `Config` trees or `project.yml`.

A clean `pod install --repo-update` resolved the public graph but Rokid's artifact host reset this environment's `RGCxrClient` archive transfer after approximately 61 seconds. That network failure is not evidence that the pod or URL is generally unavailable. To finish a byte-for-byte genuine link test without a substitute module or binary, the validation used the previously preserved 824,748-byte archive downloaded from the exact `source.http` URL in the public podspec:

```text
3dd722e595d0b94321453ec989dc1bd90813bb4080aef598e01e4aa3c2e1a243  /tmp/r.bin
3dd722e595d0b94321453ec989dc1bd90813bb4080aef598e01e4aa3c2e1a243  /tmp/RGCxrClient_1.0.4.2.framework.zip
```

The official 1.0.4 podspec was copied into the disposable build and changed only as follows:

```diff
- "http": "https://rokid-ota.oss-cn-hangzhou.aliyuncs.com/toB/Rokid_Glass/SDK/CXR-L%28iOS%29/release/RGCxrClient_1.0.4.2.framework.zip"
+ "http": "file:///tmp/RGCxrClient_1.0.4.2.framework.zip"
```

The temporary Podfile selected that copied spec with:

```ruby
pod 'RGCxrClient', :podspec => 'LocalSpecs/RGCxrClient.podspec.json'
```

No other podspec field changed. `pod install` then installed the real archive plus the genuine public-source dependencies and generated this lock graph:

```text
RGCxrClient 1.0.4 -> RGCoreKit 0.0.2 -> CocoaLumberjack/Swift 3.9.1
```

The installed RGCxrClient executable has SHA-256 `4e3458248127386d97703fe9072c83775115b1578db4a2f379671bf811829a6e`, identical to the executable extracted independently at `/tmp/rgcxr-framework.oYS60a/RGCxrClient.framework/RGCxrClient`. [Sources: public RGCxrClient and RGCoreKit podspec URLs above; generated `/tmp/rokid-genuine-current.7N6SKw/Podfile.lock`; hashes and file comparison recorded during the local validation.]

### Exact build results

The normal requested workspace command was attempted first:

```sh
xcodebuild \
  -workspace RokidLyrics.xcworkspace \
  -scheme 'Rokid Lyrics Hardware' \
  -configuration Rokid-Hardware-Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/rokid-genuine-current.7N6SKw/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

It exited 70 before compilation because this Xcode installation reported no eligible generic iOS destination: `Any iOS Device` was ineligible with `iOS 26.5 is not installed`. `xcodebuild -showsdks` can see the iPhoneOS 26.5 SDK files, but `xcrun simctl list runtimes` reports no installed runtimes. A target-mode build confirmed that `actool` also fails with `No available simulator runtimes for platform iphonesimulator`. This is a local Xcode component/runtime limitation, not a successful workspace build and not an observed defect in the Rokid framework.

To validate every Swift source, genuine framework link, and CocoaPods embed phase despite that local `actool` blocker, the real pod targets were built first with:

```sh
xcodebuild \
  -project Pods/Pods.xcodeproj \
  -target Pods-RokidLyrics \
  -configuration Rokid-Hardware-Debug \
  -sdk iphoneos \
  CONFIGURATION_BUILD_DIR=/tmp/rokid-genuine-current.7N6SKw/FinalEmbeddedBuild \
  OBJROOT=/tmp/rokid-genuine-current.7N6SKw/FinalEmbeddedObj \
  SYMROOT=/tmp/rokid-genuine-current.7N6SKw/FinalEmbeddedSym \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

That command built `CocoaLumberjack`, the genuine `RGCoreKit`, the genuine vendored `RGCxrClient`, and the `Pods-RokidLyrics` aggregate successfully for arm64 iPhoneOS. The application target was then built with the same product roots:

```sh
xcodebuild \
  -project RokidLyrics.xcodeproj \
  -target RokidLyrics \
  -configuration Rokid-Hardware-Debug \
  -sdk iphoneos \
  CONFIGURATION_BUILD_DIR=/tmp/rokid-genuine-current.7N6SKw/FinalEmbeddedBuild \
  OBJROOT=/tmp/rokid-genuine-current.7N6SKw/FinalEmbeddedObj \
  SYMROOT=/tmp/rokid-genuine-current.7N6SKw/FinalEmbeddedSym \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  EXCLUDED_SOURCE_FILE_NAMES=Assets.xcassets \
  ASSETCATALOG_COMPILER_APPICON_NAME= \
  build
```

This second command succeeded. The two asset settings were command-line-only and existed solely to bypass the missing local runtime in `actool`; they were not written into project configuration. All app and Share Extension Swift sources compiled, including the conditional Rokid coordinator, display transport, and glasses-microphone service. The final app link explicitly passed `-framework CocoaLumberjack -framework RGCoreKit -framework RGCxrClient`, and CocoaPods' embed phase copied all three genuine frameworks into the app.

The unsigned bundle exists at:

```text
/tmp/rokid-genuine-current.7N6SKw/FinalEmbeddedBuild/Rokid Lyrics.app
```

Recorded artifact sizes were:

| Artifact | Size |
| --- | ---: |
| App bundle, allocated size reported by `du` | 9,132 KiB |
| `Rokid Lyrics` arm64 executable | 4,782,264 bytes |
| Embedded `RGCxrClient` executable | 1,817,144 bytes |
| Embedded `RGCoreKit` executable | 650,160 bytes |
| Embedded `CocoaLumberjack` executable | 593,312 bytes |
| Embedded Share Extension executable | 1,466,784 bytes |

`vtool` identifies the app executable as platform iOS, minimum iOS 17.0, SDK 26.5. `otool -L` records these genuine runtime dependencies:

```text
@rpath/CocoaLumberjack.framework/CocoaLumberjack
@rpath/RGCoreKit.framework/RGCoreKit
@rpath/RGCxrClient.framework/RGCxrClient
```

The embedded RGCxrClient executable's SHA-256 remains `4e3458248127386d97703fe9072c83775115b1578db4a2f379671bf811829a6e`. `codesign -dvv` reports `code object is not signed at all`, as expected from the command. A separate minimal arm64 iOS 17 link probe referencing `CxrClient.shared` also linked against these same three real frameworks; its Mach-O load commands record all three.

This proves that the current adapter and application sources compile and link against the genuine public SDK dependency chain, and that CocoaPods can embed the real frameworks. It does **not** prove a normal asset-complete workspace build on this Mac, code signing, installation, launch, Rokid AI authorization, BLE connection, display rendering, glasses microphone streaming, background behavior, or any hardware result. Earlier 2026-08-11 interface-only checks are superseded by this genuine link evidence and are not counted as the current validation.

## Remaining blockers and unanswered questions

The following require Rokid clarification, a fully linked signed device build, or physical hardware; the inspected artifacts do not answer them sufficiently:

1. Whether the public pod/artifact may be redistributed in an open-source binary release, and the commercial-shipping approval process.
2. Any developer-account, device-model, firmware, regional Rokid AI app, serial-number, or allow-list requirements beyond the in-app authorization flow.
3. A supported simulator/XCFramework distribution; the current artifact is device arm64 only.
4. Maximum CustomView JSON/text sizes, safe update frequency, display resolution/safe area, truncation behavior, and explicit CJK font coverage.
5. Whether a CustomView remains visible when iOS suspends the companion app and exactly which events can wake it.
6. Whether glasses PCM continues while the phone is locked/backgrounded, its latency/drift characteristics, and the unit/epoch of `RGCxrClientAudioDataEvent.timestamp`.
7. Real-world effect of glasses PCM capture on simultaneous YouTube Music playback, route, battery, heat, and long-session stability.
8. Physical-device confirmation of discovery/authentication, repeated connect/disconnect, static text, rapid synthetic updates, Unicode, Shazam recognition, and the end-to-end lyric pipeline.

Do not mark any of those items complete without direct evidence.
