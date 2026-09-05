# Monetization — free forever, WinRAR + donations

## Model
The app is **free for life, fully functional, no ads, no subscription, no
account.** Two optional ways to pay:

1. **One-time "Full" purchase** (WinRAR model) — IAP non-consumable.
   Optional. The free app already works; this is a "support the developer"
   unlock of the premium tier (T1/T2 features) if we gate any.
2. **Donations** — optional, via external web link.

## Store policy (critical)
- **Apple (3.1.1 / 3.2.1):** You may NOT sell features or the full version via
  an external link (PayPal/Stripe) — that must be IAP. Donations/gifts to a
  third party are allowed if they unlock **nothing** in-app and 100% goes to
  the recipient. Flow: "Support the developer" → Safari → donation page.
- **Google Play:** A tip/donation to the creator with **no digital
  consideration** can sit outside Play Billing, but it's a misclassification
  risk — document the flow with screenshots and keep it clearly optional.
- **Rule for both:** a donation must never unlock a badge, theme, or feature.
  Keep donations 100% thank-you, not transactional.

## Colombia reality (Diego is in CO)
- **Stripe** does not operate directly in Colombia.
- **PayPal.me** — simplest.
- **Ko-fi / Buy Me a Coffee** — work, creator-friendly.
- Recommendation: PayPal.me primary, Ko-fi secondary.

## Costs
- Apple Developer: $99/year.
- Google Play: $25 one-time.
- Store commission on IAP: 30% (15% via Apple Small Business / Google small-dev
  if under ~$1M/yr).

## Maintenance-minimal stance
- No backend → nothing to host, scale, or secure.
- No accounts → no support load, no data, no GDPR surface.
- The only ongoing cost is: keep Flutter/PDFium current + answer bug reports.
- Add Crashlytics/Sentry (free tier) + a feedback channel to cut support load.
