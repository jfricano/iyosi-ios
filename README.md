# iYosi for iOS

An informational guide to designated and community-reported smoking areas in Metro Manila. The app distinguishes reviewed information from unverified reports so people can respect smoke-free rules and shared air.

Open [iYosi.xcodeproj](iYosi.xcodeproj) in Xcode 16 or later and run the `iYosi` scheme on an iOS 17+ simulator or device. The app uses SwiftUI and MapKit with no package dependencies. To regenerate the project after adding a Swift file, run `python3 generate_project.py` from this repository root.

## API setup

Start the separate iYosi API using its README. When all three repositories are checked out locally, the API is in the sibling `api/` folder. The iOS Simulator defaults to `http://localhost:8000`. From the app's Account screen, open **API server settings** to enter a different base URL. Remote URLs must use HTTPS; changing the server signs out the current account. A physical iPhone needs a reachable HTTPS endpoint. Browsing is anonymous; registration and sign-in are needed only for contributions.

Address and landmark search calls the API's `/v1/address-suggestions` endpoint. It shows a configuration message until the API operator sets `GEOAPIFY_API_KEY` or a compatible `GEOCODER_URL`. Geoapify results include provider and OpenStreetMap attribution links. Map imagery uses Apple Maps. The app asks for foreground location only after **Near me** is tapped.

## Included flows

- Adult-access prompt and pilot privacy notice.
- NCR map with capped viewport pagination, simple zoom-level clustering, distinct type symbols, independent type/status filters, and optional prohibited warning pins.
- Place detail with evidence-review and confirmation dates shown separately, reviews, observations, access notes, and directions only when the API permits them.
- Adult account registration, sign-in, Keychain token storage, proposal tracking, and deletion request.
- New place and correction proposals with map-selected area and entrance pins, nearby duplicate lookup, and pending-review acknowledgement.
- Confirmations, ratings/written reviews, and reports sent to the v1 API with idempotency keys for retryable POSTs.

The admin moderation interface and public-launch age assurance/privacy operations remain separate project work. A new place is never published directly by this app.

## Verification

The project builds for a generic iOS Simulator with Xcode 27.0 and the iOS 27.0 SDK (`CODE_SIGNING_ALLOWED=NO`). It has been installed and launched on an iPhone 18 Pro simulator against the isolated synthetic demo API, which shows four fictional pins and working local address suggestions. The normal database contains no published places until an administrator publishes reviewed submissions.

## License

Copyright © 2026 Orca Solutions. All rights reserved. See [LICENSE.md](LICENSE.md). Public visibility does not make this app open source.
