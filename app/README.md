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
    model/                     reading mode, view rotation, PDF source
    services/                  system document picker, last-page store
    ui/                        viewer screen, panels, toolbars
  features/pages/
    logic/                     pure plan transforms, page-range parsing
    model/                     page plan entries
    services/                  PDFium-backed encoder, save dialog
    ui/                        page organiser screen
  features/annotate/
    annotation_controller.dart state shared by the layer, toolbar and panel
    logic/                     coordinate mapping, hit testing, text snapping
    model/                     annotation types, tools, style
    services/                  annotation store
    ui/                        drawing layer, painter, toolbar, panel
```

Each feature's `logic/` deliberately has no pdfrx imports so the maths is
unit-testable without a PDFium document. In the viewer,
`logic/pdfrx_layout_adapter.dart` is the only bridge; in page operations, the
plan is a plain list of page references and `services/pdf_page_editor.dart`
turns it into real pages.

The page organiser never edits the document the viewer has open: it opens its
own copies, edits a plan, and writes a new file only when you save.

Annotations are stored in **normalised page space** — 0–1 across the page,
origin top-left — so zoom, reading mode and view rotation all just move the
page rectangle the viewer reports, and the same numbers map onto it.
`annotate/logic/page_coordinates.dart` is that mapping. Annotations persist
per document on-device; they are not yet written into the PDF file itself
(see the roadmap note in `docs/SPEC.md` §3).

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
