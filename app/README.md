# app — The PDF Project (Flutter)

The Flutter client for The PDF Project: a free-for-life PDF reader & editor for
iOS and Android by SoftMind AI. Everything runs on-device — no backend, no
accounts, no network calls.

Feature scope lives in `../docs/SPEC.md`; this module currently implements the
T0 viewer.

## Stack

| Concern | Package |
|---|---|
| PDF rendering / text / outline | `pdfrx` (PDFium) |
| PDF generation (test fixtures) | `pdf` |
| Document picking | `file_picker` |
| Paths | `path_provider` |

## Layout

```
lib/
  app.dart                     MaterialApp + theming wiring
  core/                        theme, app-wide view preferences
  features/viewer/
    logic/                     pure page-layout + navigation maths
    model/                     reading mode, PDF source
    services/                  system document picker
    ui/                        viewer screen, panels, toolbars
```

`logic/` deliberately has no pdfrx imports so the maths is unit-testable
without a PDFium document; `logic/pdfrx_layout_adapter.dart` is the only bridge.

## Commands

```sh
flutter pub get
flutter analyze
flutter test
flutter test --exclude-tags pdfium   # skip tests that load the native library
flutter run                          # needs a connected iOS/Android device
```

## Test fixtures

`test/fixtures/sample.pdf` is a generated three-page document. Regenerate it
with:

```sh
dart run tool/generate_fixture_pdf.dart test/fixtures/sample.pdf
```
