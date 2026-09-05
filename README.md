# The PDF Project

A free-for-life, no-ads, no-subscription PDF reader & editor for iOS and
Android. Built by **SoftMind AI** (softmindai.com).

The pitch: everything the paid PDF apps do, on-device, free forever.
Monetization is optional — a one-time "full version" purchase (WinRAR model)
and/or donations. No ads. No account. No server.

## Status
- Framework: **Flutter** (single codebase, iOS + Android)
- PDF engine: **PDFium** (via `pdfrx`) — MIT, native performance
- OCR: **Google ML Kit** — free, on-device
- Build scope: see `docs/SPEC.md` (T0 = MVP)

## Repository layout
- `docs/SPEC.md` — exhaustive feature list + build tiers
- `docs/ARCHITECTURE.md` — tech stack & design
- `docs/MONETIZATION.md` — WinRAR + donations model, store policy
- `CLAUDE.md` — project context for the AI builder
- `app/` — Flutter source (MVP)

## Monetization
Free forever. Optional one-time purchase (IAP non-consumable) and/or
donations via external web link (see `docs/MONETIZATION.md`).

## License
Source: see `LICENSE`. (Choose before public release — default MIT.)
