# The PDF Project — Builder Context

You are building **The PDF Project**, a free-for-life PDF reader & editor for
iOS + Android, by SoftMind AI (softmindai.com).

## Hard constraints
- Framework: **Flutter**, single codebase, iOS + Android.
- PDF engine: **`pdfrx`** (PDFium, MIT). Use `pdf` (Dart) for generation/merge.
- OCR: **Google ML Kit** (on-device, free).
- **100% on-device for MVP. No backend. No accounts. No network for core.**
- **No ads. No subscription.** Monetization = optional one-time IAP + external
  donation link only (see docs/MONETIZATION.md).
- Build scope: **T0 items in docs/SPEC.md only** for the MVP. Do not start T1/T2.

## Build order (MVP)
1. Flutter project scaffold (app/), iOS + Android targets.
2. Viewer: open PDF, render, zoom, pan, page nav, outline, thumbnails, search.
3. Page ops: merge, split, reorder, rotate, delete, insert blank.
4. Annotations: ink, shapes, text box, highlight, sticky note, eraser,
   edit/delete. Coordinate mapping overlay is the hardest part — get it right.
5. Signature: draw / type / image, place on page.
6. Forms: fill AcroForm fields + save.
7. Security: open password-protected PDFs.
8. Image→PDF.
9. Share: print + system share sheet.
10. Library: recent files, open-from-picker.

## Conventions
- Dart effective style, `flutter analyze` clean.
- Feature modules under `app/lib/features/<name>/`.
- Tests: unit + widget + integration (open→annotate→save round-trip).
- Fixture PDFs under `app/test/fixtures/` (encrypted, form, scanned, large).
- Keep it offline-first; no third-party runtime network calls in MVP.

## When unsure
Prefer the simplest on-device solution that ships. If a feature needs a
backend or a paid SDK, STOP and ask (do not silently add a backend or a paid
dependency). Report what you built and what's next.
