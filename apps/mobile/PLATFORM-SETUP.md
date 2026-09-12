# Platform setup (run once Flutter is installed)

`android/` and `ios/` now contain a hand-written **minimum** subset of what
`flutter create --platforms=android,ios .` produces — enough to describe the
Phase-0 policy decisions (min SDK, no dangerous permissions/services, iOS 16
target) but NOT a complete, buildable host project. This pass wrote:

- `android/settings.gradle.kts`, `android/build.gradle.kts`,
  `android/gradle.properties`, `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/kunim/app/MainActivity.kt`
- `android/app/src/main/res/values/styles.xml` +
  `android/app/src/main/res/drawable/launch_background.xml`
- `ios/Runner/Info.plist`, `ios/Runner/AppDelegate.swift`

What it deliberately did **not** attempt to hand-write, because these are
either binary/semi-binary, machine-specific, or asset-generation artifacts
that `flutter create` regenerates far more reliably than a hand-typed copy
would:

- `android/gradle/wrapper/gradle-wrapper.{jar,properties}`, `gradlew`,
  `gradlew.bat`, `android/local.properties` (points at the Flutter SDK path
  on *this* machine — inherently machine-specific)
- Launcher icons (`android/app/src/main/res/mipmap-*/ic_launcher.png`)
- `ios/Runner.xcodeproj/project.pbxproj`, `ios/Runner.xcworkspace`,
  `ios/Runner/Assets.xcassets`, `ios/Runner/Base.lproj/{LaunchScreen,Main}.storyboard`,
  `ios/Podfile`
- Any `key.properties` / release signing configuration

**Do this on a machine with Flutter installed, before the first real build:**

```
cd apps/mobile
flutter create --platforms=android,ios --org com.kunim --project-name kunim .
```

Then diff `flutter create`'s output against the files already present here
and reconcile — in particular:

## Android (`android/app/src/main/AndroidManifest.xml`)
- `minSdk = 26` (Android 8+, per plan) is already set in
  `android/app/build.gradle.kts` — confirm `flutter create` doesn't reset it.
- No extra permissions beyond `INTERNET` in Phase 0. Do **not** add
  `PACKAGE_USAGE_STATS`, `QUERY_ALL_PACKAGES`, `SYSTEM_ALERT_WINDOW`, or an
  `AccessibilityService` — those are Phase 6 (Digital Wellbeing) and are
  policy-restricted per `CLAUDE.md`.
- The manifest already has a `<queries>` block scoped to a single
  `ACTION_MAIN`/`LAUNCHER` intent (not a package-visibility blanket grant).

## iOS (`ios/Runner/Info.plist`)
- Set the deployment target to iOS 16.0 in the regenerated Xcode project
  (`IPHONEOS_DEPLOYMENT_TARGET` — there is no Info.plist key for this).
- No extra `Info.plist` usage-description keys are needed in Phase 0.
- **Apple Developer portal (manual, not a file edit):** submit the request
  for the `com.apple.developer.family-controls` entitlement now — per
  `docs/plan.md` section 12, Phase 0's Definition of Done includes "iOS
  Family Controls entitlement so'rovi yuborilgan" (approval can take
  weeks and gates Phase 6 iOS Digital Wellbeing, not this phase's build).
