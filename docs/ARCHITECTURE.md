# Architecture

## Goal
A single Flutter codebase shipping to iOS + Android. 100% on-device for the
MVP: no backend, no accounts, no network required for core features. This is
what keeps maintenance minimal.

## Stack
| Concern | Choice | Why |
|---|---|---|
| Framework | Flutter | Best OSS PDF engine access, single codebase |
| PDF engine | PDFium via `pdfrx` | MIT, native speed, render + page ops |
| PDF creation | `pdf` (Dart) | Generate/merge PDFs in Dart |
| OCR | Google ML Kit | Free, on-device, no backend |
| State | Riverpod or Bloc | Predictable state |
| Storage | `path_provider` + `sqflite` (library index) | Local only |
| Camera | `image_picker` + `camera` | Scan feature |

## Module map
- `viewer/` — render, zoom, pan, page nav, search, outline, thumbnails
- `annotate/` — ink, shapes, text, highlight, sticky notes, eraser (overlay canvas)
- `signature/` — draw / type / image signature, place on page
- `forms/` — AcroForm field fill + save
- `pages/` — merge, split, reorder, rotate, insert, delete
- `security/` — open encrypted, set/remove password, permissions
- `scan/` — camera capture, edge detect, filter, save as PDF
- `convert/` — image→PDF (T0); PDF→Word/Excel (T1, native libs)
- `library/` — recent files, favorites, local browser, search
- `share/` — print, system share, export to image/text

## Key technical risks
1. **Annotation overlay** — mapping canvas coordinates ↔ PDF page coordinates
   with zoom/rotation. The single hardest MVP piece.
2. **AcroForm fill** — reading field widgets and writing values back correctly.
3. **Encrypted PDFs** — PDFium handles most; edge cases with owner-password
   permission bits.
4. **Large PDFs** — memory on low-end Android. Use PDFium's lazy page load.
5. **Conversion (T1)** — PDF→Word needs a heavy native lib or backend; keep
   out of MVP.

## Testing
- Unit: coordinate mapping, page-op logic, form field serialization.
- Widget: viewer + annotation overlay.
- Integration: open→annotate→save round-trip on a fixture PDF.
- Fixture PDFs: encrypted, form-heavy, scanned, large, multi-font.
