# iOS review status (October 2026)

This is the handoff for the independent iOS review, which ran alongside reviews of the Android app (iyosi-android PR #1) and the API (iyosi-api PR #2). Everything below is committed on branch `claude/project-thread-d74j9t` in this PR.

## State

- **Merged before building.** The app isn't live, so the project owner chose to merge PR #2 before compiling it. The first Xcode build after the merge may need small compile fixes. After that, run the dev-mode checks below.
- **Branch:** `claude/project-thread-d74j9t`. PR jfricano/iyosi-ios#2, based on `main` (`dbbdea1`).
- **Not compiled yet.** The review ran without Xcode. The first step when picking this up is to build in Xcode (iOS 17 target, Swift 5.9). Then smoke-test the flows listed under "Verify".
- **API compatibility:** this branch works against iyosi-api `main` (`71d7af6`) and against iyosi-api PR #2. The only thing that depends on the API PR is review prefill and delete. Without that PR, the review form simply starts blank, as it did before.

## What changed

| Commit | Change | Files |
|---|---|---|
| `cb8d83e` | Superseded map loads no longer show "Places could not load". `URLSession` throws `URLError(.cancelled)`, so `APIClient` now rethrows `CancellationError` when the task is cancelled. The account is rechecked every time the app returns to the foreground. | `APIClient.swift`, `iYosiApp.swift` |
| `f1d841f` | Fixes shared with the Android review: <br>• A 401 for the current token signs the user out (`APIClient.onUnauthenticated`, wired in `AppState.api`). <br>• Shows the first 422 `field_errors` entry. <br>• Requires an email of at least 5 characters. <br>• Caps address search at 100 Unicode scalars. <br>• Drops a token that arrives after the server setting changed. <br>• A merged place links to its current record. <br>• The observation picker goes back 29 days, not 30. | `APIClient.swift`, `Models.swift`, `AppState.swift`, `AccountView.swift`, `MapHomeView.swift`, `PlaceDetailView.swift` |
| `62694b0` | The review form prefills from `GET /v1/places/{id}/reviews/me` and shows "Delete my review" only when a review exists. A 404 or 405 means "no review / old server", and the form starts blank. A cross-field 422 (`field: "body"`) is shown without the field name. | `APIClient.swift` (`myReview`, `deleteMyReview`, new `send` helper for no-content responses), `Models.swift`, `PlaceDetailView.swift` |
| `c9e38c9` | The privacy notice and the deletion confirmation now say what an approved deletion removes: reviews are removed and no longer count toward ratings, the free text in submissions, confirmations, and reports is blanked, and published places stay. This matches iyosi-api#2 and Android's wording. | `iYosiApp.swift`, `AccountView.swift` |

## Testing in dev mode

1. Start the API locally from iyosi-api: `docker compose up -d --build`, then `curl http://localhost:8000/health`. Use the branch from iyosi-api PR #2 to exercise review prefill/delete and the new deletion behaviour. For fictional seeded places and working address search, use the demo stack on port 8001 (`docs/DEMO_DATA.md` in iyosi-api).
2. Build the `iYosi` scheme in Xcode (Debug) and run it in the iOS Simulator. The app defaults to `http://localhost:8000` (in every build, which is the open production-host item below). For the demo stack, set Account → Server settings to `http://localhost:8001`. A physical device needs the Mac's `.local` hostname, since only `localhost`, `127.0.0.1` and `*.local` are allowed over HTTP.
3. Register an account in the app, then promote it to admin with `docker compose exec workspace python scripts/grant_admin.py EMAIL`, so you can publish test places and approve a deletion from `http://localhost:8000/admin`.
4. Run the checks below. To check layouts without any API, set the scheme environment variable `IYOSI_DESIGN_PREVIEW=1`. That runs the app on fictional fixtures (`DesignPreview.swift`).

## Verify after building

1. Pan the map quickly while places load. No error banner should remain once the pins appear.
2. Sign in, then make the token invalid: restart a local API with a different `IYOSI_SECRET`, or wait 24 h. Trying to confirm a place, or bringing the app back to the foreground, should show the sign-in form.
3. Submit a proposal with a 5-character basis. The error should read "Check the submitted fields: basis, …".
4. On an API with PR #2: save a review, reopen "Rate or review", and check that the stars and text are filled in. Then delete the review. On an API without PR #2, the form should open blank with no error.
5. Open a merged place. "Open the current record" should open the canonical place.
6. Change the API server in Account while a sign-in is in progress. The app should not end up signed in.
7. Request account deletion. The confirmation should describe what gets removed. Approve it in the admin console, and check that your review is gone and the place's rating count has dropped.
8. With the API stopped, browsing should show "Places could not load" and Retry. It should not crash, and it should recover once the API is back.

## API decisions (iyosi-api PR #2, final as of Oct 4)

Full detail is in the project's `reviews/api.md`.

- **Contract additions (C1–C5):** `GET reviews/me` (used here), newest-first reviews and confirmations, 10-minute `observed_at` slack, `expires_at` on tokens, and login length caps. None of these require an iOS change.
- **R4, account deletion: approved.** Reviews are removed and free text is blanked. The iOS copy is updated in `c9e38c9`. If that API change is ever dropped, revert this copy.
- **R2, correction publish: approved.** Corrections keep blank optional fields and the place's current status. Server-only.
- **R3, connection pooling: approved.** It adds a 503 `database_busy` response, which iOS shows as the server message. No change.
- **R1, per-account rate limits:** no client work.
- **R5 (duplicate override) and R7 (password reset):** not planned. Either one would need new iOS UI, a "submit anyway" option and account screens respectively.
- **When iyosi-api PR #2 merges,** re-run verify steps 4 and 7 against that server.

## Still open (iOS)

- **Production API host.** Release builds default to `http://localhost:8000` (`AppState.init`), and Android has the same gap. Once the project picks the HTTPS host, set it as the release default and keep localhost for DEBUG only.
- **No iOS CI.** The repo has no workflow, so nothing builds it automatically. A macOS GitHub Actions job running `xcodebuild -scheme iYosi -destination 'generic/platform=iOS Simulator' build` would catch compile errors before merge.
- **Process-level state.** Form text is lost if the app is killed mid-form. This was accepted for the pilot, the same as Android.

## Related

- Project files: `reviews/ios.md`, `reviews/android.md`, `reviews/api.md` (the shared review notes from all three threads).
- iyosi-android PR #1 (Android rewrite) and iyosi-api PR #2 (API fixes from the review).
