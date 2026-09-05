# The PDF Project — Feature Specification

Full parity target with paid PDF apps (Adobe Acrobat Reader, Foxit, Xodo,
PDF Expert, iLovePDF). Organized by capability. Each feature is tagged with a
build tier:

- **T0 (MVP)** — must be in the first shippable build. On-device, no backend.
- **T1 (V2)** — high value, build after MVP is stable.
- **T2 (stretch)** — hard / needs native libs or backend. Nice-to-have.

Legend: `[T0]` `[T1]` `[T2]`

---

## 1. Viewing & Navigation
- [T0] Open and render PDF (local file, from other apps, shared)
- [T0] Pinch-to-zoom, zoom in/out buttons, fit-width / fit-height / fit-page
- [T0] Pan / scroll (vertical + horizontal)
- [T0] Page navigation: first / prev / next / last, jump-to-page
- [T0] Document outline / bookmarks panel (TOC)
- [T0] Thumbnail / page-list side panel
- [T0] In-document text search (find, next/prev, highlight matches)
- [T0] Reading modes: single page, continuous scroll, two-page spread
- [T0] View rotation (90°/180°/270°)
- [T0] Dark mode / night theme
- [T0] Remember last opened page per document
- [T1] Full-screen mode
- [T1] Custom zoom presets & default zoom setting
- [T1] Search across all documents (index local library)
- [T1] Page layout grid / margin options
- [T1] Multi-window / split view (tablet)
- [T2] 3D / page-flip transition effects

## 2. Text
- [T0] Text selection (drag)
- [T0] Copy selected text
- [T0] Select all
- [T1] Extract text → export .txt
- [T1] Text-to-speech / read-aloud
- [T1] Dictionary lookup / search web for selection
- [T1] Translate selected text (on-device or light API)
- [T2] Language detection per page

## 3. Annotations
- [T0] Freehand ink / drawing
- [T0] Shapes: rectangle, ellipse, line, arrow
- [T0] Text box annotation
- [T0] Highlight (multi-color presets)
- [T0] Underline / strikethrough
- [T0] Sticky note / comment
- [T0] Eraser (remove annotations)
- [T0] Edit / move / delete existing annotations
- [T0] Annotation toolbar: color, thickness, opacity
- [T1] Callout / stamp annotations
- [T1] Annotation layers (show/hide groups)
- [T1] Pin / unpin annotations
- [T1] Annotation history / undo-redo
- [T2] Redaction (permanent black-out with content removal)

## 4. Signature
- [T0] Draw signature (canvas)
- [T0] Type signature (font rendering)
- [T0] Insert signature from image
- [T0] Place signature on page, resize/move
- [T1] Reusable saved signatures
- [T1] Date-stamped signature
- [T2] Digital signature (PKI / certificate, verification)

## 5. Forms
- [T0] Fill AcroForm text fields
- [T0] Checkboxes
- [T0] Radio buttons
- [T0] Dropdown / combo boxes
- [T0] Save filled form
- [T1] Form validation (required fields, patterns)
- [T1] Flatten form (make fields permanent)
- [T1] Multi-page form navigation
- [T2] XFA forms (legacy Adobe)

## 6. Page Operations
- [T0] Delete page(s)
- [T0] Reorder / drag pages
- [T0] Merge multiple PDFs into one
- [T0] Split PDF (by page range / extract pages)
- [T0] Rotate page(s)
- [T0] Insert blank page
- [T1] Crop page(s)
- [T1] Insert existing PDF/image as pages
- [T1] Add page numbers
- [T1] Watermark (text or image, tiled)
- [T1] Header / footer
- [T1] Add image to a page
- [T1] Change page size / trim box
- [T2] Form overlay / custom page templates

## 7. Security & Permissions
- [T0] Open password-protected (user password) PDFs
- [T1] Set user password (open)
- [T1] Set owner password + permissions (no print/copy/edit)
- [T1] Remove password
- [T1] Show document security / permission info
- [T2] AES-256 encryption control
- [T2] Certificate-based restrictions

## 8. Print & Share
- [T0] Print (system print dialog)
- [T0] Share via system share sheet (AirDrop, email, WhatsApp, etc.)
- [T0] Save to Files / Documents
- [T1] Export page(s) to image (PNG/JPG)
- [T1] Export selected text
- [T1] Add to Home Screen (wrap as web shortcut)
- [T1] Generate QR code from PDF / link
- [T1] Send to other apps (open-with)
- [T2] Print to specific printer settings (duplex, range)

## 9. Conversion
- [T0] Image → PDF (JPG/PNG → PDF, multi-image)
- [T1] PDF → images (whole doc)
- [T1] PDF → Word (.docx)
- [T1] PDF → Excel (.xlsx)
- [T1] PDF → PowerPoint (.pptx)
- [T1] Word/Excel/PowerPoint → PDF
- [T1] HTML / URL → PDF
- [T2] PDF ↔ e-book (EPUB)
- [T2] OCR-based editable conversion (scanned → editable doc)

## 10. Scan / Camera
- [T0] Scan document with camera
- [T0] Auto edge detection
- [T0] Filters: color, B&W, grayscale, enhance
- [T0] Save scan as PDF (single + multi-page)
- [T1] Capture barcode / QR
- [T1] Perspective correction
- [T1] Page count / reorder scans
- [T2] Auto-categorize / classify scans

## 11. Organization & Files
- [T0] Recent files list
- [T0] Open-from-any-app (document picker)
- [T1] Favorites / pin
- [T1] Local file browser with folders
- [T1] Search library by name
- [T1] Rename / move / delete
- [T1] Tags
- [T2] Cloud sync (iCloud / Drive / Dropbox) — needs backend/auth
- [T2] Import from email attachments

## 12. Productivity & AI
- [T1] Compress / optimize PDF (reduce size, re-encode images)
- [T1] Repair corrupted PDF
- [T1] Edit document metadata (title, author, subject)
- [T1] OCR — make scanned PDF searchable (on-device, ML Kit)
- [T1] Compare two documents (diff)
- [T2] AI summary of document
- [T2] AI Q&A / chat on document (on-device LLM or API)
- [T2] PDF/A archival validation
- [T2] Document templates

## 13. System / Platform
- [T0] Fully offline (no network required for core)
- [T0] Accessibility: screen reader (VoiceOver / TalkBack)
- [T0] Light + dark theme
- [T0] iOS + Android from single codebase
- [T1] Widgets (recent files)
- [T1] App shortcuts / deep links
- [T1] Keyboard shortcuts (hardware keyboard)
- [T1] Backup / restore annotations
- [T2] Multi-device sync (needs backend)

---

## MVP definition (T0 only)
The first shippable build = every `[T0]` item. This is a genuinely
competitive free PDF app with **no ads, no subscription, no account,
100% on-device**. T1/T2 are roadmap.

## Non-goals for MVP
- No backend, no user accounts, no cloud sync.
- No server-side conversion (PDF→Word etc. are T1/T2).
- No digital PKI signatures (T2).
