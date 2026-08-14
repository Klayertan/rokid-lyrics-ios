# Physical iPhone setup

> **Procedure status:** This is a setup guide, not a test result. Completing it does not prove microphone coexistence, live Shazam matching, App Group transfer, Rokid authorization, or hardware behavior. Record those results in [`DEVICE_TEST_SESSION.md`](DEVICE_TEST_SESSION.md).

This guide takes a new contributor from a clean clone to a development-signed install on a physical iPhone. Start with the public **Rokid Lyrics Mock** configuration. Configure the optional proprietary SDK only after the mock build launches successfully.

If you do not have a paid Apple Developer Program membership, skip directly to [Free Apple Account / Personal Team](#free-apple-account--personal-team) and use the **Rokid Lyrics Personal** scheme instead; see [`docs/PERSONAL_TEAM_MODE.md`](PERSONAL_TEAM_MODE.md) for what that build does and does not include.

The project targets iOS 17 or later. Apple recommends a physical device for features and conditions a simulator cannot reproduce, and documents automatic signing as the normal way to register a connected device and create a development provisioning profile: [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

## What you need

- A Mac with a current stable Xcode release and the iOS platform installed.
- An iPhone running iOS 17 or later, its passcode, and a data-capable USB cable for initial pairing.
- An Apple Account added to Xcode.
- An Apple Developer team that can use **App Groups** and the **ShazamKit** App Service. Apple notes that available capabilities depend on program membership; a Personal Team may not expose everything this project needs: [Adding capabilities to your app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app) and [Supported capabilities (iOS)](https://developer.apple.com/help/account/reference/supported-capabilities-ios/).
- Account Holder or Admin help if your team role cannot register identifiers or App Groups. Apple lists those roles for [registering an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id) and [registering an App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group).
- [XcodeGen 2.46.0 or later](https://github.com/yonaskolb/XcodeGen) to regenerate the Xcode project.
- Network access for signing, Shazam catalog matching, LRCLIB lookup, and optional artwork loading.

Do not commit a Team ID, signing certificate, provisioning profile, Apple credentials, Rokid credentials, SDK archive, `Pods/`, or `Config/Local.xcconfig`.

## 1. Clone and inspect the project

1. Open **Terminal**.
2. Clone the repository and enter it:

   ```sh
   git clone https://github.com/Klayertan/rokid-lyrics-ios.git
   cd rokid-lyrics-ios
   ```

3. Confirm that the expected local configuration template exists:

   ```sh
   test -f Config/Local.xcconfig.example
   ```

4. Install XcodeGen if `xcodegen --version` is unavailable. With Homebrew:

   ```sh
   brew install xcodegen
   ```

5. Do not open or edit `RokidLyrics.xcodeproj` yet. It is generated from `project.yml`.

## 2. Choose four unique identifiers

Choose values owned by your Apple Developer team. Do not reuse another app's identifiers.

| Local setting | What to enter | Rule |
| --- | --- | --- |
| `ROKID_LYRICS_DEVELOPMENT_TEAM` | Your Team ID | Copy it from your signed-in Apple Developer membership details; enter it without quotes. |
| `ROKID_LYRICS_BUNDLE_ID` | Main-app bundle ID | A unique reverse-DNS identifier, for example one based on a domain or name you control. |
| `ROKID_LYRICS_SHARE_BUNDLE_ID` | Share-extension bundle ID | Must be unique and different from the main app; using the main ID plus `.ShareExtension` is conventional. |
| `ROKID_LYRICS_APP_GROUP` | Shared App Group ID | Must begin with `group.` and must be assigned to both App IDs. Apple documents the prefix requirement in [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups). |

Bundle IDs are exact identifiers: capitalization and punctuation must match in the developer portal and local configuration. Apple requires an explicit App ID's bundle ID to match the target's bundle ID: [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id).

## 3. Register the App Group in the Apple Developer portal

1. Open [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list) and sign in.
2. Select **Identifiers** in the left sidebar.
3. Click the **+** button.
4. Select **App Groups**, then click **Continue**.
5. Enter a description such as `Rokid Lyrics shared data`.
6. Enter the exact value chosen for `ROKID_LYRICS_APP_GROUP`.
7. Click **Continue**, review the value, then click **Register**.

These are Apple's documented registration steps: [Register an App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group).

## 4. Register the main app ID

1. Still under **Identifiers**, click **+**.
2. Select **App IDs**, then click **Continue**.
3. Leave **App** selected as the App ID type, then click **Continue**.
4. Enter a description such as `Rokid Lyrics iOS`.
5. Select **Explicit**.
6. Enter the exact `ROKID_LYRICS_BUNDLE_ID` value.
7. Under **Capabilities**, enable **App Groups**.
8. Configure App Groups and select the exact `ROKID_LYRICS_APP_GROUP` registered above.
9. Under **App Services**, enable **ShazamKit**.
10. Click **Continue**, review all values, then click **Register**.

Apple's ShazamKit account guide requires the ShazamKit checkbox under the App ID's **App Services** tab for catalog access: [ShazamKit service setup](https://developer.apple.com/help/account/services/shazamkit/). ShazamKit is an App ID service in this project; do not invent a `com.apple.developer.shazamkit` entitlement.

If the main App ID already exists:

1. Open it under **Identifiers**.
2. Click **Edit** if shown.
3. Enable **App Groups**, click **Configure**, select `ROKID_LYRICS_APP_GROUP`, and assign it.
4. Open **App Services**, enable **ShazamKit**, and save.
5. Allow Xcode to refresh signing assets later. Apple warns that changing an App ID's capabilities invalidates affected provisioning profiles: [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/).

## 5. Register the Share extension app ID

1. Under **Identifiers**, click **+**.
2. Select **App IDs** and then **App**, clicking **Continue** after each choice.
3. Enter a description such as `Rokid Lyrics Share Extension`.
4. Select **Explicit**.
5. Enter the exact `ROKID_LYRICS_SHARE_BUNDLE_ID` value.
6. Enable **App Groups**.
7. Configure App Groups and select the same `ROKID_LYRICS_APP_GROUP` used by the main app.
8. Click **Continue**, review the values, then click **Register**.

Do not enable ShazamKit for the Share extension. It only accepts supported share-sheet items and places one confirmed draft in the shared App Group. Apple documents App Groups as the supported way for a containing app and extension from the same team to share a container: [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups). The project uses `UserDefaults(suiteName:)`, for which Apple says to pass the App Group identifier: [`UserDefaults.init(suiteName:)`](https://developer.apple.com/documentation/foundation/userdefaults/init%28suitename%3A%29).

## 6. Create the private local build configuration

1. Back in Terminal at the repository root, copy the tracked template:

   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

2. Open `Config/Local.xcconfig` in a plain-text editor.
3. Set the developer-owned values and review all six settings. Keep the two mode defaults Mock-safe; the named schemes own SDK compilation settings:

   ```xcconfig
   ROKID_LYRICS_DEVELOPMENT_TEAM = YOUR_TEAM_ID
   ROKID_LYRICS_BUNDLE_ID = com.yourcompany.rokidlyrics
   ROKID_LYRICS_SHARE_BUNDLE_ID = $(ROKID_LYRICS_BUNDLE_ID).ShareExtension
   ROKID_LYRICS_APP_GROUP = group.$(ROKID_LYRICS_BUNDLE_ID).shared
   ROKID_LYRICS_BUILD_MODE = mock
   ROKID_LYRICS_DEFAULT_MOCK_MODE = YES
   ```

4. Replace `YOUR_TEAM_ID` and `com.yourcompany.rokidlyrics` with the values registered for your team. The example derives the Share-extension and App Group identifiers from the main bundle ID; if you use different registered values, enter those exact values instead. Do not add quotation marks.
5. Save the file.
6. Confirm Git ignores it:

   ```sh
   git status --short --ignored Config/Local.xcconfig
   ```

   The output should identify the file as ignored, not as a new tracked file.

The four identity settings feed the generated targets and entitlements; the two build-mode settings are exposed to the app as configuration metadata. Do not add SDK feature flags or Swift compilation conditions to this local file: **Rokid Lyrics Mock** and **Rokid Lyrics Hardware** supply them through dedicated configurations. Changing only an Xcode text field is not durable because a later `xcodegen generate` replaces the generated project.

## 7. Generate and open the mock project

1. Generate the project:

   ```sh
   xcodegen generate
   ```

2. Open it:

   ```sh
   open RokidLyrics.xcodeproj
   ```

3. In Xcode's top toolbar, open the scheme menu.
4. Select **Rokid Lyrics Mock**.
5. Do not select **Rokid Lyrics Hardware** for the first install.

The legacy **RokidLyrics** Debug/Release configurations also remain forced to mock behavior, but the named Mock scheme makes the evidence category explicit.

## 8. Add the Apple Account to Xcode

1. In Xcode, choose **Xcode → Settings**.
2. Select **Accounts**.
3. Click **+**.
4. Select **Apple Account** and sign in.
5. Select the team whose Team ID you placed in `ROKID_LYRICS_DEVELOPMENT_TEAM`.
6. Close Settings.

Apple's device-running guide directs developers to add their account under **Xcode → Settings → Accounts**, assign the targets to a team, and use automatic signing: [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

## 9. Verify signing for both targets

Do this verification without changing identifiers in the generated project.

1. In Xcode's Project navigator, select the blue **RokidLyrics** project.
2. Under **TARGETS**, select **RokidLyrics**.
3. Open **Signing & Capabilities**.
4. Confirm **Automatically manage signing** is enabled.
5. Confirm the selected **Team** is the intended team.
6. Confirm **Bundle Identifier** resolves to the value of `ROKID_LYRICS_BUNDLE_ID`.
7. Under **TARGETS**, select **RokidLyricsShareExtension**.
8. Open **Signing & Capabilities**.
9. Confirm automatic signing, the same team, and the `ROKID_LYRICS_SHARE_BUNDLE_ID` value.
10. Confirm the App Group entitlement resolves to the same `ROKID_LYRICS_APP_GROUP` for both targets.

Do not add a made-up ShazamKit entitlement in Xcode. If the portal service is enabled and signing is correct, the app uses the public ShazamKit framework and catalog service as documented by Apple: [`SHSession`](https://developer.apple.com/documentation/shazamkit/shsession/).

If Xcode says a provisioning profile does not include the App Group, return to the portal and verify that the same group is assigned to both explicit App IDs. Then, in Xcode, toggle automatic signing off and back on only if needed to force a refresh; do not delete unrelated certificates or profiles.

## 10. Pair the iPhone

1. Connect the iPhone to the Mac with a data-capable USB cable.
2. Unlock the iPhone.
3. If the iPhone asks whether to trust the computer, tap **Trust** and enter the device passcode.
4. In Xcode, open **Window → Devices and Simulators** or **Device Hub**, depending on the Xcode version.
5. Select the iPhone and wait for pairing and any support-file preparation to finish.
6. In the main Xcode window, open the run-destination menu next to the scheme.
7. Select the physical iPhone, not a Simulator and not **Any iOS Device**.

With automatic signing, Xcode can register the attached device and update the development profile. Apple documents the trust prompt and automatic device registration in [Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

## 11. Enable Developer Mode on the iPhone

Developer Mode normally appears only after pairing begins.

1. On the iPhone, open **Settings**.
2. Open **Privacy & Security**.
3. Scroll to **Security** and tap **Developer Mode**.
4. Turn **Developer Mode** on.
5. Tap **Restart** in the warning.
6. After restart, unlock the iPhone.
7. Tap **Enable** in the confirmation dialog.
8. Enter the iPhone passcode.

These are Apple's current steps: [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device). Developer Mode permits development-signed apps to run; it is not needed for ordinary App Store or TestFlight installation.

## 12. Build, install, and launch Mock Mode

1. Return to Xcode.
2. Confirm the scheme is **Rokid Lyrics Mock**.
3. Confirm the selected destination is the physical iPhone.
4. Choose **Product → Run**, or click the triangular Run button.
5. If Xcode offers to register the device or repair signing, review the selected team and then allow it.
6. Wait for both the app and Share extension to build and for **Rokid Lyrics** to launch on the iPhone.
7. If iOS reports an untrusted developer, follow the on-device prompt to the developer-app trust setting, trust only your own team, then run again.
8. In the app, open **Settings**.
9. Confirm **Developer / Mock Mode** is on.
10. Open **Rokid** and confirm the capability view identifies the mock build rather than claiming physical hardware.

A successful install proves only that this signed build launched on this iPhone. It does not prove any live service or hardware result.

## 13. Grant microphone permission deliberately

The project includes `NSMicrophoneUsageDescription`, which Apple requires for microphone access: [`NSMicrophoneUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription). The app requests recording permission through public AVFAudio APIs only after a recognition action.

1. Make sure no private conversation is occurring near the phone.
2. Open the app's **Home** tab.
3. Tap **Start Lyrics**.
4. Read the iOS permission prompt.
5. Tap **Allow** only if you intend to run the acoustic-recognition tests.
6. Confirm the app displays a visible microphone/listening state and iOS shows its microphone privacy indicator.
7. Tap **Stop** immediately for this setup check.
8. Confirm the app no longer reports the microphone as active.

Apple documents recording as requiring user permission and recommends `AVAudioApplication` for current permission handling: [`AVAudioApplication`](https://developer.apple.com/documentation/avfaudio/avaudioapplication). If permission was denied, open **Settings → Privacy & Security → Microphone** and enable **Rokid Lyrics** before a recognition test. Do not repeatedly reinstall merely to bypass a deliberate denial.

## 14. Verify the Share extension is present

1. Open YouTube Music, Safari, or Notes on the iPhone with a harmless test URL or synthetic text selected.
2. Open the standard iOS Share sheet.
3. Scroll through the app row and tap **More** if needed.
4. Find **Share to Rokid Lyrics** and enable it as a favorite if desired.
5. Open it and confirm the same **Share to Rokid Lyrics** heading appears.
6. Confirm it requires both **Song title** and **Artist** before **Save for Rokid Lyrics** becomes available.
7. Tap **Cancel** for this setup-only check.

Apple documents that a Share extension receives the initial text and attachments supplied through its extension context; the host controls what it supplies: [App Extension Programming Guide — Share](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html). Do not infer a stable YouTube Music payload from the extension merely appearing.

## 15. Optional command-line build check

After the device has been paired and signing works in Xcode, this command builds the explicit mock configuration for a generic iOS device. It does not install or launch the app:

```sh
xcodebuild \
  -project RokidLyrics.xcodeproj \
  -scheme 'Rokid Lyrics Mock' \
  -configuration Mock-Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  build
```

The Team ID and bundle identifiers come from `Config/Local.xcconfig`; do not append a real `DEVELOPMENT_TEAM` value to a shared command or script.

## 16. Optional Rokid Hardware configuration

Do not begin here until the Mock scheme signs, installs, and launches. This section prepares a build; it does not establish hardware compatibility or a passed device test.

1. Read [`ROKID_SDK_NOTES.md`](ROKID_SDK_NOTES.md), including licensing, binary-slice, authorization, and logging warnings.
2. Obtain the official SDK through the documented source and accept its terms yourself.
3. Keep proprietary artifacts outside version control.
4. Install CocoaPods if needed:

   ```sh
   brew install cocoapods
   ```

5. From the repository root, prepare the local Podfile, regenerate the project, and install the workspace integration:

   ```sh
   cp Config/Podfile.hardware.example Podfile
   xcodegen generate
   pod install
   open RokidLyrics.xcworkspace
   ```

6. Leave all six `Config/Local.xcconfig` settings as configured above. The **Rokid Lyrics Hardware** scheme overrides the two Mock-safe mode defaults and supplies its SDK compilation condition through the dedicated Hardware configuration; do not add hardware-only flags to the local file.
7. In Xcode, select **Rokid Lyrics Hardware** and the physical iPhone.
8. Never select an iOS Simulator for this configuration; the inspected proprietary framework has no Simulator slice.
9. Verify both targets still resolve to the intended team, bundle IDs, and App Group.
10. Build and install. Treat success only as a linked/signed device build until authorization, discovery, display, audio, and reconnect tests are actually recorded.

## Free Apple Account / Personal Team

This section installs **Rokid Lyrics Personal** on your own iPhone with a free Apple ID and no paid Apple Developer Program membership. It replaces sections 2–9 above: it does not register an App ID, an App Group, or the ShazamKit App Service in the Apple Developer portal, because the `RokidLyricsPersonal` target requests none of those capabilities. See [`docs/PERSONAL_TEAM_MODE.md`](PERSONAL_TEAM_MODE.md) for exactly what this build does and does not include, and why.

Complete [1. Clone and inspect the project](#1-clone-and-inspect-the-project) first so Xcode, XcodeGen, and the repository are ready.

1. Create your local configuration and set a unique bundle ID you control:

   ```sh
   cp Config/Local.xcconfig.example Config/Local.xcconfig
   ```

   Edit `ROKID_LYRICS_BUNDLE_ID` in `Config/Local.xcconfig` to a reverse-DNS identifier you control, for example based on your name. Leave `ROKID_LYRICS_DEVELOPMENT_TEAM` blank — Personal Team signing does not use a typed Team ID the way a paid membership does; Xcode assigns your Personal Team once you select it in Signing & Capabilities in step 10 below.

2. Generate and open the project:

   ```sh
   xcodegen generate
   open RokidLyrics.xcodeproj
   ```

3. In Xcode, choose **Xcode → Settings**.
4. Select **Accounts**.
5. Click **+**, select **Apple Account**, and sign in with your regular (free) Apple ID.
6. Xcode creates a **Personal Team** named after your Apple Account, shown in the Team list as "\<Your Name\> (Personal Team)." No paid enrollment is required to reach this state. Apple documents adding an account and using automatic signing at [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).
7. Close Settings.
8. In Xcode's scheme menu, select **Rokid Lyrics Personal**.
9. Connect your iPhone with a data-capable USB cable, unlock it, and select it as the run destination — not a Simulator and not **Any iOS Device**.
10. In the Project navigator, select the blue **RokidLyrics** project, then the **RokidLyricsPersonal** target, then open **Signing & Capabilities**.
11. Confirm **Automatically manage signing** is enabled.
12. Set **Team** to your Personal Team.
13. Confirm **Bundle Identifier** resolves to your `ROKID_LYRICS_BUNDLE_ID` value and that Xcode reports no signing error. `Rokid Lyrics Personal` has no capability cards in this tab by design — its entitlements file is empty — so there is nothing else to configure here.
14. On the iPhone, enable Developer Mode: **Settings → Privacy & Security → Security → Developer Mode**, turn it on, tap **Restart**, unlock after restart, then tap **Enable** and enter the passcode. This is Apple's documented procedure: [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
15. If the iPhone asks whether to trust the computer, tap **Trust** and enter the passcode. In Xcode, open **Window → Devices and Simulators** (or **Device Hub**) and let pairing finish.
16. In Xcode, choose **Product → Run**. If Xcode offers to register the device or repair signing, review the selected Personal Team and allow it.
17. If iOS reports an untrusted developer, open **Settings → General → VPN & Device Management** on the iPhone, trust your own Apple Account, and run again.

### Bundle identifier requirements

A Personal Team can sign any bundle identifier you have not already registered elsewhere under that Apple ID, following the same reverse-DNS uniqueness rule as a paid account: [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id). `Rokid Lyrics Personal` intentionally reuses the same `ROKID_LYRICS_BUNDLE_ID` value as the main app target rather than introducing a second identifier to manage; it does not need a Share Extension identifier at all, because that target is never built for this scheme.

### Provisioning validity

Expect to periodically re-run **Product → Run** from Xcode to reinstall the app as its free/Personal Team development provisioning profile ages, particularly after the device has not been reconnected to Xcode for a while. This project has not verified a specific validity period against current, official Apple documentation, and public reports of the exact duration vary; do not treat any specific number of days as authoritative here. Re-running from Xcode with the device connected is the supported recovery step regardless of the exact duration.

### What this path does not require

Unlike the numbered sections above, Free Apple Account / Personal Team setup does not involve registering an App ID in the Apple Developer portal, registering an App Group, enabling the ShazamKit App Service, or an Account Holder/Admin role. If you later enroll in the paid Apple Developer Program, follow the numbered sections above for the full **Rokid Lyrics Mock** or **Rokid Lyrics Hardware** capabilities; see the upgrade path in [`docs/PERSONAL_TEAM_MODE.md`](PERSONAL_TEAM_MODE.md#upgrade-path). Nothing about completing this section changes or removes the other two schemes.

## Troubleshooting without destructive changes

### The Team menu is empty

Return to **Xcode → Settings → Accounts**, sign in, and select the intended team. If this is an organization, ask its Account Holder or Admin to confirm your access. Do not borrow another person's certificate.

### A bundle identifier is unavailable

Choose a new unique identifier you control, update the appropriate local variable, register the exact new App ID, and regenerate. Do not delete or overwrite an unrelated identifier.

### The App Group entitlement is rejected

Verify all three copies of the identity agree: the registered group, the group assigned to each App ID, and `ROKID_LYRICS_APP_GROUP`. Apple describes the portal assignment flow in [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/).

### ShazamKit reports a service or catalog error

Verify ShazamKit is enabled under **App Services** for the exact main App ID used to sign this build. Refresh signing assets and test again on the physical iPhone with network access. Do not add an undocumented entitlement.

### Developer Mode is missing

Reconnect and unlock the iPhone, accept the trust prompt, and begin pairing in Xcode. Apple notes that Developer Mode appears after pairing is initiated or the device has previously been paired: [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).

### The Share extension does not appear or transfer data

Confirm it was embedded in the installed app, both targets use the same team, and both resolve to the same registered App Group. Delete and reinstall this development build only if ordinary rebuild/reinstall does not refresh it; deleting the app also removes local test data.

### The hardware framework fails on Simulator

Use the **Rokid Lyrics Mock** scheme for Simulator/public work and the **Rokid Lyrics Hardware** scheme only with a physical iPhone. Do not modify the proprietary framework or fabricate a Simulator slice.

## Setup completion checklist

- [ ] `Config/Local.xcconfig` exists locally and is ignored by Git.
- [ ] The main and Share-extension bundle IDs are unique and registered.
- [ ] The same registered App Group is assigned to both App IDs.
- [ ] ShazamKit is enabled for the main App ID only.
- [ ] Xcode uses automatic signing and the intended team for both targets.
- [ ] The physical iPhone is paired and Developer Mode is enabled.
- [ ] **Rokid Lyrics Mock** installs and launches.
- [ ] Microphone permission behavior has been deliberately checked.
- [ ] **Share to Rokid Lyrics** appears in a standard Share sheet.
- [ ] No live-service, Simulator, or hardware result has been inferred from setup alone.

Proceed to [`YOUTUBE_MUSIC_DEVICE_TEST.md`](YOUTUBE_MUSIC_DEVICE_TEST.md) and record observations in [`DEVICE_TEST_SESSION.md`](DEVICE_TEST_SESSION.md).

## Official sources

- Apple: [Running your app on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- Apple: [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- Apple: [Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
- Apple: [Adding capabilities to your app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app)
- Apple: [Register an App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id)
- Apple: [Register an App Group](https://developer.apple.com/help/account/identifiers/register-an-app-group)
- Apple: [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/)
- Apple: [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
- Apple: [ShazamKit service setup](https://developer.apple.com/help/account/services/shazamkit/)
- Apple: [`NSMicrophoneUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription)
- Apple: [`AVAudioApplication`](https://developer.apple.com/documentation/avfaudio/avaudioapplication)
- Apple: [`SHSession`](https://developer.apple.com/documentation/shazamkit/shsession/)
- Apple: [`UserDefaults.init(suiteName:)`](https://developer.apple.com/documentation/foundation/userdefaults/init%28suitename%3A%29)
- Apple: [App Extension Programming Guide — Share](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html)
