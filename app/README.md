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
| Preferences (last page read) | `shared_preferences` |
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

Both fixtures are generated and byte-for-byte reproducible, so regenerating
them does not churn the repository.

| Fixture | What it is |
|---|---|
| `test/fixtures/sample.pdf` | Three plain pages with searchable text |
| `test/fixtures/encrypted.pdf` | One page, standard security R3 (128-bit RC4), user password `letmein` |

```sh
dart run tool/generate_fixture_pdf.dart test/fixtures/sample.pdf
dart run tool/generate_encrypted_fixture_pdf.dart test/fixtures/encrypted.pdf
```
