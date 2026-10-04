# iOS review status (October 2026)

This is the handoff for the independent iOS review, which ran alongside reviews of the Android app (iyosi-android PR #1) and the API (iyosi-api PR #2). Everything below is committed on branch `claude/project-thread-d74j9t` in this PR.

## State

- **Branch:** `claude/project-thread-d74j9t`. Draft PR jfricano/iyosi-ios#2, three commits on top of `main` (`dbbdea1`).
- **Not compiled yet.** The review ran without Xcode. The first step when picking this up is to build in Xcode (iOS 17 target, Swift 5.9). Then smoke-test the flows listed under "Verify".
- **API compatibility:** this branch works against iyosi-api `main` (`71d7af6`) and against iyosi-api PR #2. The only thing that depends on the API PR is review prefill and delete. Without that PR, the review form simply starts blank, as it did before.

## What changed

| Commit | Change | Files |
|---|---|---|
| `cb8d83e` | Superseded map loads no longer show "Places could not load". `URLSession` throws `URLError(.cancelled)`, so `APIClient` now rethrows `CancellationError` when the task is cancelled. The account is rechecked every time the app returns to the foreground. | `APIClient.swift`, `iYosiApp.swift` |
| `f1d841f` | Fixes shared with the Android review: <br>• A 401 for the current token signs the user out (`APIClient.onUnauthenticated`, wired in `AppState.api`). <br>• Shows the first 422 `field_errors` entry. <br>• Requires an email of at least 5 characters. <br>• Caps address search at 100 Unicode scalars. <br>• Drops a token that arrives after the server setting changed. <br>• A merged place links to its current record. <br>• The observation picker goes back 29 days, not 30. | `APIClient.swift`, `Models.swift`, `AppState.swift`, `AccountView.swift`, `MapHomeView.swift`, `PlaceDetailView.swift` |
| `62694b0` | The review form prefills from `GET /v1/places/{id}/reviews/me` and shows "Delete my review" only when a review exists. A 404 or 405 means "no review / old server", and the form starts blank. A cross-field 422 (`field: "body"`) is shown without the field name. | `APIClient.swift` (`myReview`, `deleteMyReview`, new `send` helper for no-content responses), `Models.swift`, `PlaceDetailView.swift` |

## Verify after building

1. Pan the map quickly while places load. No error banner should remain once the pins appear.
2. Sign in, then make the token invalid: restart a local API with a different `IYOSI_SECRET`, or wait 24 h. Trying to confirm a place, or bringing the app back to the foreground, should show the sign-in form.
3. Submit a proposal with a 5-character basis. The error should read "Check the submitted fields: basis, …".
4. On an API with PR #2: save a review, reopen "Rate or review", and check that the stars and text are filled in. Then delete the review. On an API without PR #2, the form should open blank with no error.
5. Open a merged place. "Open the current record" should open the canonical place.
6. Change the API server in Account while a sign-in is in progress. The app should not end up signed in.

## Waiting on the API review's decisions

The API thread is still working through these tradeoffs (see the project's `reviews/api.md`). Each one would need iOS work if adopted:

- **R5, duplicate override.** If the API adds an `acknowledge_nearby` flag, `SubmissionView` needs a way to submit anyway. Today it disables Submit whenever a place is within 50 m (`closeDuplicates`).
- **R4, deleting content with an account: decided and done.** iyosi-api#2 now removes the person's reviews and blanks their free text when an admin approves the deletion. The privacy notice and the deletion confirmation in this PR say so. If that API change is dropped, revert this copy.
- **R2, correction publish: decided.** Corrections now keep blank optional fields and the place's current status. This is server-only.
- **R7, password change or reset, token revocation.** If these are added, they need new Account screens.
- **R1, per-account rate limits.** No iOS change is expected, because iOS already shows 429 messages from the server.
- **R3** is server-only.
- **When iyosi-api PR #2 merges,** nothing changes in iOS. Re-run verify step 4 against the deployed server.

## Still open (iOS)

- **Production API host.** Release builds default to `http://localhost:8000` (`AppState.init`), and Android has the same gap. Once the project picks the HTTPS host, set it as the release default and keep localhost for DEBUG only.
- **No iOS CI.** The repo has no workflow, so nothing builds it automatically. A macOS GitHub Actions job running `xcodebuild -scheme iYosi -destination 'generic/platform=iOS Simulator' build` would catch compile errors before merge.
- **Process-level state.** Form text is lost if the app is killed mid-form. This was accepted for the pilot, the same as Android.

## Related

- Project files: `reviews/ios.md`, `reviews/android.md`, `reviews/api.md` (the shared review notes from all three threads).
- iyosi-android PR #1 (Android rewrite) and iyosi-api PR #2 (API fixes from the review).
