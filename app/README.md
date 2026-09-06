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
| Print and share sheet | `printing` |
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
    logic/                     coordinate mapping, hit testing, text snapping,
                               resize handles, PDF geometry and appearances
    model/                     annotation types, tools, style
    services/                  annotation store, PDF annotation writer
    ui/                        drawing layer, painter, toolbar, panel
  features/signature/
    logic/                     cropping a drawing, placing it on a page
    model/                     drawn, typed and image signatures
    ui/                        the signature pad
  features/forms/
    logic/                     what changed, what a field will accept
    model/                     fields, their kinds and their controls
    services/                  PDFium form reading and filling
    ui/                        the form filler and its per-kind editors
  features/share/
    services/                  saving, sharing and printing a finished PDF
    ui/                        the destination sheet
  features/library/
    logic/                     keeping the recents list in order
    model/                     a remembered document
    services/                  the recents store, and copies of picked files
    ui/                        the home screen
  features/convert/
    logic/                     page shapes, and the order of the pages
    model/                     a picked image
    services/                  choosing images, building the PDF
    ui/                        the images-to-PDF screen
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
`annotate/logic/page_coordinates.dart` is that mapping.

Annotations persist per document on-device, and "Save a copy with
annotations" writes them into a PDF as real PDF annotations.
`annotate/services/pdf_annotation_writer.dart` does that through PDFium's C
API, which pdfrx exposes via `useNativeDocumentHandle`; the coordinate
conversion it needs lives in `annotate/logic/pdf_page_geometry.dart` and the
drawing instructions for the shapes PDFium will not draw itself in
`annotate/logic/annotation_appearance.dart`.

A signature is captured in `features/signature/` and then placed as a
`SignatureAnnotation`, so it inherits the annotation feature's placement,
selection, moving, resizing and export rather than repeating any of it.

With no document open the viewer shows the library: what has been read
recently, and a way to open something else. A recents entry is keyed the same
way as the rest of the app keys a document, so the page it was left on and the
annotations on it follow it around. Documents picked as raw bytes — Android's
picker often hands back a content URI with no file behind it — are copied into
the app's own folder so the entry still opens later; those copies are deleted
when the entry falls off the end of the list.

"Images to PDF" on the home screen turns photos or scans into a document, one
page each. Every page is exactly the shape of its picture and the picture
fills it, which keeps the arrangement to a single instruction and lets a
JPEG's own bytes go into the document untouched — an album of photographs does
not swell on the way in. Paper sizes, margins and cropping are not offered:
placing a picture *within* a page means positioning it in PDF coordinates, and
that is unfinished work rather than a decision.

The recents list lives in shared preferences rather than a database: it is
capped at 30 small records, so there is nothing a query would help with. A
database earns its place when the library grows into something searchable.

Every screen that produces a PDF — the organiser, the form filler, the
annotation export, and the viewer itself — hands it to the same destination
sheet, so saving to Files, the system share sheet and the print dialog are
reachable from all of them. Sharing from the viewer sends the annotated copy
when the document has annotations, and the sheet says so rather than quietly
sending something different from what is on screen.

Form filling goes through PDFium's form API rather than writing values into
the document by hand: the app focuses a field and types into it, clicks a tick
box, chooses an option — so PDFium redraws each field itself. Every
interaction is followed by dropping focus, because PDFium keeps an edit in the
focused widget until focus moves on.

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
| `test/fixtures/form.pdf` | An AcroForm with a text field, a tick box, a two-button radio group and a dropdown |

```sh
dart run tool/generate_fixture_pdf.dart test/fixtures/sample.pdf
dart run tool/generate_encrypted_fixture_pdf.dart test/fixtures/encrypted.pdf
dart run tool/generate_form_fixture_pdf.dart test/fixtures/form.pdf
```
