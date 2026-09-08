# App Store and TestFlight preparation

## Current target

Prepare TestFlight before public App Store submission. The release candidate is
1.1.0; retain the existing bundle identifier so development updates preserve app
data. Do not invent an App Store Connect app ID or change the bundle identifier
without checking the owner's registered app record.

## Prepared

- Release archive at `.trailguard/Aurora-v1.1.0.xcarchive` (local, not committed).
- In-app terms, AI limitations, safety notices, and privacy notice, dated
  September 7, 2026; acknowledgment schema 2.
- Root MIT license with separate model/content notices.
- App privacy manifest for app-only UserDefaults and disk-space checks.
- Signed optional BioCLIP package served through the existing R2 endpoint.

## Owner/account inputs still required

- Apple Developer Program membership and App Store Connect sign-in.
- Confirm the App Store Connect app record and registered bundle identifier.
- Public support contact and a publicly accessible privacy-policy URL. The
  private GitHub README is not a public privacy-policy page.
- Confirm distribution countries, age-rating answers, content rights, export
  compliance answers, price, and App Review contact details.
- Review App Privacy answers against hosting-provider logs and all bundled SDKs;
  offline inference alone does not settle Apple's collection disclosures.

## Review notes draft

Aurora Survival is an offline educational wilderness reference and on-device AI
assistant. Manual is available without a model. Optional model downloads require
network connectivity and storage. Species ID covers 504 North American animals
and presents likely matches, not a certainty or edibility assessment. Cloudflare
serves downloadable files; inference and selected-photo processing run locally.

Test on an iPhone 13 or newer supported device. The initial R2 development
endpoint may throttle downloads. Allow model preparation to finish before the
first identification; model loading is slower than subsequent predictions.
No public submission should describe this as certified medical, rescue, or
wildlife-identification advice.

## Submission sequence

1. Complete final safety and manual camera/library review.
2. Validate the archive and resolve signing, privacy, and content-rights warnings.
3. Upload to the confirmed App Store Connect app; do not accept new agreements
   on the owner's behalf.
4. Complete TestFlight information and start with internal testing. External
   testers may require Beta App Review.
5. Submit publicly only after owner approval and completed store metadata.

References checked September 7, 2026:
[Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/),
[TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).
