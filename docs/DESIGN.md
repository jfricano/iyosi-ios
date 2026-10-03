# Landing design in the native app

The approved reference is the separate `iyosi-landing` repository's `docs/DESIGN_HANDOFF.md`, production `dist/`, and editable `design-preview/`. This implementation carries its city-guide direction through welcome/privacy, map/list, place card/detail, account, and contribution forms.

## Native design decisions

- `GuideTheme.swift` centralizes the warm paper, white card, ink, teal, amber, and terracotta palette, with adaptive dark colors. Small accent text uses darker teal/amber variants for contrast.
- Avenir Next scales with native text styles; Georgia supplies short editorial accents. Labels wrap at large text sizes. Status combines text, shape, and color.
- Search precedes the real MapKit map or list. A compact place sheet shows type, status, last confirmation, and access information before opening full details. The sheet fetches current details rather than treating the map summary as current access information.
- Evidence review dates and community confirmation dates remain separate. Ratings and reports do not grant permission. Closure and prohibition warnings precede actions; the API still controls directions availability.
- The original fictional city illustration and pin artwork match the landing page. The illustration is labeled fictional. `generate_icon.py` redraws the SVG pin using the standard library.
- Location is requested only after **Near me**, including when permission was previously granted. Browsing remains anonymous.

## Read-only simulator preview

The DEBUG-only `DesignPreview.swift` supplies fictional records in memory for visual review without a backend. It intercepts API requests, rejects writes, isolates account credentials and adult-access decline state, and disables directions to synthetic coordinates. Release builds exclude the fixture implementation.

In Xcode, build the Debug scheme for a simulator, then add these environment variables to the scheme's Run action:

| Variable | Value |
| --- | --- |
| `IYOSI_DESIGN_PREVIEW` | `1` |
| `IYOSI_DESIGN_SCREEN` | `welcome`, `map`, `map-card`, `list`, `account`, `submission`, `reviewed`, `community`, `disputed`, `prohibited`, or `closed` |
| `IYOSI_DESIGN_SIGNED_IN` | Optional `1` to show signed-in account/submission layouts |
| `IYOSI_DESIGN_LARGE_TYPE` | Optional `1` for accessibility text size |

Remove these variables to use the normal app and configured API. Preview mode defaults to the map if no screen is specified. The banner labels the fixture session; it is not part of the production UI. Apple Maps still loads map imagery.

## Verification, October 2, 2026

- Debug and Release builds: generic arm64 iOS Simulator, Xcode 27.0 / iOS 27 SDK, signing disabled.
- Rendered checks: welcome, real map with fictional pins, compact map card, list, account, contribution form, reviewed detail, prohibited detail in dark appearance, and community detail at accessibility text size.
- Reviewed contrast, touch targets, status distinctions, date semantics, preview isolation, and navigation/auth-sheet dismissal in source.
- Live backend authentication and contribution writes were not exercised during this design check. The demo backend stayed stopped.

### Screenshots

All records shown are fictional. These captures demonstrate layout, not actual designations or geographic destinations.

- [Welcome](design/welcome.png)
- [Map and compact place card](design/map-card.png)
- [Prohibited detail in dark appearance](design/prohibited-dark.png)
