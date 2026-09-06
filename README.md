# The PDF Project

A free-for-life, no-ads, no-subscription PDF reader & editor for iOS and
Android. Built by **SoftMind AI** (softmindai.com).

The pitch: everything the paid PDF apps do, on-device, free forever.
Monetization is optional — a one-time "full version" purchase (WinRAR model)
and/or donations. No ads. No account. No server.

## Status

The T0 (MVP) scope of `docs/SPEC.md` is built:

- **Viewer** — open from the file picker, render, pinch-zoom, pan, page
  navigation, jump-to-page, outline panel, thumbnails, text search, single-page
  and continuous modes, two-page spread, rotation, fit-height, last page
  remembered, password-protected documents, dark mode
- **Page operations** — delete, reorder, rotate, merge, split, insert blank
- **Annotations** — ink, shapes, text box, highlight, sticky note, eraser,
  colours and weights, an annotations panel, and export into a real PDF
- **Signatures** — drawn, typed or from a photo, placed, moved and resized
- **Forms** — fill AcroForm text fields, tick boxes, radio groups, dropdowns
- **Print and share** — system share sheet, save-to-Files, print dialog
- **Library** — recent documents on the home screen
- **Images → PDF** and **camera scanning** with edge detection and filters

Not yet done: no build has ever been produced for a real device (see
[Before the first release](#before-the-first-release)).

- Framework: **Flutter** (single codebase, iOS + Android)
- PDF engine: **PDFium** (via `pdfrx`) — MIT, native performance
- OCR: **Google ML Kit** — free, on-device (T1, not yet started)
- Build scope: see `docs/SPEC.md` (T0 = MVP)

## Requirements

| | Version | Notes |
|---|---|---|
| Flutter | 3.47.0 or newer (built against 3.47.2 stable) | `pdfrx` requires it |
| Dart | 3.13 or newer | ships with Flutter |
| JDK | 17 | Android only; the Gradle build targets Java 17 |
| Android SDK | platform 36, NDK `28.2.13676358` | Android only |
| Xcode | current stable, on macOS | iOS only |
| CocoaPods | current stable | iOS only |

Run `flutter doctor` and fix anything it reports for the platform you intend
to build.

**The first build of each platform needs a network connection.** PDFium is not
vendored: `pdfium_flutter` downloads the Android binaries as a Dart native
asset at build time, and fetches an XCFramework through CocoaPods/SwiftPM for
iOS. That is a build-time download only — the app itself makes no network
calls at runtime, and nothing it opens or produces leaves the device.

## Getting started

```sh
git clone https://github.com/ddarthp/the-pdf-project.git
cd the-pdf-project/app
flutter pub get
flutter run              # with a device or emulator/simulator connected
```

All Flutter commands are run from `app/`, not the repository root.

`flutter run` picks whichever device is attached; `flutter devices` lists
them and `-d <id>` chooses one.

## Building for Android

```sh
cd app
flutter build apk                      # release APK
flutter build apk --debug              # debug APK
flutter build apk --split-per-abi      # one APK per architecture, much smaller
flutter build appbundle                # AAB for Play
```

Output lands in `app/build/app/outputs/`.

Configuration, all in `app/android/app/build.gradle.kts`:

| | |
|---|---|
| Application ID | `com.softmindai.the_pdf_project` |
| `minSdk` | 24 (Flutter's default) |
| `targetSdk` / `compileSdk` | 36 (Flutter's defaults) |
| Java / Kotlin JVM target | 17 |
| AGP / Gradle | 9.1.0 / 9.3.1 |

Two things a fresh clone will not have, both by design:

- **`android/local.properties`** is not committed. The Flutter tool writes it
  (with `flutter.sdk` and `sdk.dir`) the first time you run a `flutter` command
  that touches Android. Invoking Gradle directly before that fails with
  `flutter.sdk not set in local.properties`.
- **The Gradle wrapper JAR and `gradlew`** are not committed either, which is
  standard for a Flutter project. Drive Android builds through `flutter build`
  rather than `./gradlew`.

Release builds are currently **signed with the debug keystore** so that
`flutter run --release` works out of the box. That must be replaced before any
release — see [Before the first release](#before-the-first-release).

## Building for iOS

iOS builds require macOS with Xcode; there is no way to produce one from Linux
or Windows.

```sh
cd app
flutter build ios --release --no-codesign   # no signing identity needed
flutter build ipa                           # signed archive for the App Store
open ios/Runner.xcworkspace                 # to set the signing team, then Archive
```

| | |
|---|---|
| Bundle identifier | `com.softmindai.thePdfProject` |
| Deployment target | iOS 15.0 |
| Workspace | `app/ios/Runner.xcworkspace` (not the `.xcodeproj`) |

`app/ios/Podfile` and `Pods/` are not committed. The Flutter tool generates the
Podfile and runs `pod install` on the first iOS build; run `pod install` from
`app/ios` by hand if you are working in Xcode directly. That install is what
fetches the PDFium XCFramework, so it needs network access the first time.

For a device build you need an Apple Developer team selected: open
`Runner.xcworkspace`, choose the Runner target → Signing & Capabilities, and
set your team.

## Permissions the app asks for

The scanner and images→PDF both go through the system camera and photo picker.

**iOS** (`app/ios/Runner/Info.plist`) declares `NSCameraUsageDescription` and
`NSPhotoLibraryUsageDescription`. Both strings are shown verbatim in the system
prompt and read by App Review.

**Android** (`app/android/app/src/main/AndroidManifest.xml`) declares **no**
runtime permissions at all, deliberately:

- Capture is handed to whatever camera app is installed via
  `ACTION_IMAGE_CAPTURE`, which needs no permission of ours. Declaring
  `CAMERA` would actively make things worse — `image_picker` requests it at
  runtime only when it finds it in the merged manifest, so the declaration
  would create a prompt the app does not otherwise need.
- Pictures and documents arrive through the system photo picker and document
  picker, which hand back only what the user selected, so no media-read
  permission applies.
- Nothing talks to the network, so release builds have no `INTERNET`
  permission. The debug and profile manifests add it for hot reload only.

There is one `<queries>` entry for `ACTION_IMAGE_CAPTURE`: on Android 11+
package-visibility filtering would otherwise hide every camera app from the
lookup `image_picker` uses to grant it write access to the captured file.

## Tests and analysis

```sh
cd app
flutter analyze                      # must be clean
flutter test                         # 503 tests
flutter test --exclude-tags pdfium   # skip tests that load the native library
```

Many tests are widget tests backed by the real PDFium, and several verify PDF
output by encoding a document, reopening it and asserting on what PDFium reads
back. They are tagged `pdfium` so they can be excluded where the native asset
cannot be built.

The three fixture PDFs under `app/test/fixtures/` are committed, and
reproducible byte-for-byte from the generators in `app/tool/` — see
`app/README.md` for the commands.

## Repository layout

- `README.md` — this file
- `BUILDER.md` — project context and constraints for the AI builder
- `docs/SPEC.md` — exhaustive feature list + build tiers (T0/T1/T2)
- `docs/ARCHITECTURE.md` — tech stack & design
- `docs/MONETIZATION.md` — WinRAR + donations model, store policy
- `app/` — the Flutter application
- `app/README.md` — how the code is organised and why, feature by feature

Each feature lives in `app/lib/features/<name>/`, split into `logic/` (pure,
no PDF engine imports, unit-testable), `model/`, `services/` (the seams onto
the platform and PDFium) and `ui/`.

## Branches

Work landed one feature per branch off `master`:
`feat/mvp-viewer`, `feat/mvp-page-ops`, `feat/mvp-annotations`,
`feat/mvp-annotation-export`, `feat/mvp-signature`, `feat/mvp-forms`,
`feat/mvp-share`, `feat/mvp-library`, `feat/mvp-convert`, `feat/mvp-scan`,
`feat/mvp-permissions`. Each builds on the one before it; none has been merged
to `master` yet.

## Before the first release

Known gaps, none of them hidden:

- **Nothing has been built for a device.** `flutter build apk` and
  `flutter build ios` have never run — the machine this was written on has no
  Android SDK and is not a Mac. Six plugins' platform code, the manifest
  merge, the permission prompts and PDFium's native packaging are all
  unverified on real hardware. This is the next thing to do.
- **Release signing** uses the debug keystore. Create a keystore, add
  `android/key.properties` (already gitignored) and a real `signingConfig`.
- **Display names** are still the scaffold's: `the_pdf_project` on Android,
  "The Pdf Project" on iOS. Both need setting to "The PDF Project".
- **App icons** are the default Flutter icons.
- **Images→PDF page presets** (A4/Letter, margins, fit) are deliberately not
  offered: placing a picture *within* a page rather than filling it produced a
  wrong render that was not resolved. Every page is currently the exact shape
  of its picture. See `app/README.md`.
- **Text selection and copy** come from `pdfrx`'s own selection layer with
  no configuration of ours, and nothing here asserts on them. Worth checking
  by hand on the first device build.
- **T1 and beyond** — OCR, redaction, compression — have not been started.

## Monetization

Free forever. Optional one-time purchase (IAP non-consumable) and/or
donations via external web link (see `docs/MONETIZATION.md`).

## License

Not chosen yet, and there is no `LICENSE` file. Pick one before any public
release — the default intention is MIT, which is also what PDFium and `pdfrx`
are under.
