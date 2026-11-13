# Apps on this iPhone: installing, seeing and renewing apps outside Cartouche

Date: 2026-11-13. Status: built the same day, as decision 88 in
[docs/decisions.md](../../decisions.md); the plan is beside it in `../plans/`.

## Intent

Cartouche carries a complete SideStore, and today uses it for itself alone:
signing in, renewing Cartouche, updating Cartouche. The player wants what a
standalone SideStore gives on top of that: install an IPA as a normal iOS
app, outside Cartouche's LiveContainer, see those apps, and renew them
before their seven-day signature runs out. Everything on Cartouche's own
screens: no page of SideStore's ever shows (decision 24).

## Goals

- **Install an IPA on this iPhone** from Cartouche: pick the IPA in Files,
  SideStore signs it with the player's Apple ID and installs it as its own
  app on the home screen.
- **See** the apps Cartouche installed this way: name, when their signature
  expires, when they were last renewed; **Open** each one.
- **Renew** them: one app at a time from its row, all of them with
  Cartouche's **Renew now**, and every night with the Shortcuts automation
  Cartouche already sets up.
- **Uninstall** such an app from Cartouche.
- Failures say why, as SideStore left it, with a report to copy, like a
  failed renewal or update today.

## Non-goals

- SideStore's sources, browsing, updates from sources, backups, the active
  and inactive juggling of apps, its widget.
- JIT for these apps: StikDebug handles a normal iOS app by itself.
- Installing on the iPhone from the games folder, or Import asking where an
  IPA goes: Import keeps installing inside Cartouche.
- Apps that another SideStore or AltStore of the same Apple ID installed:
  Cartouche shows, renews and removes only what it installed itself.
- The imported-signing mode (decision 78): a p12 and its profile sign
  Cartouche alone, so nothing can be installed beside it. The section says
  so and offers nothing.
- Anything in the Cartouche Installer.

## Anti-goals

- Touching another store's apps: renewing or removing an app the player's
  own SideStore installed is the failure patch 0017 was made for.
- Any SideStore screen, prompt or toast reaching the player.
- An install that stops half-way without a word, or that leaves the IPA copy
  behind in the app group.

## Constraints

- Free Apple ID: three active apps at once, Cartouche being one, so two apps
  outside it; ten App IDs every seven days, an app with extensions taking
  one per extension; seven-day signatures. SideStore counts apps, not their
  extensions, against the three (`activeAppLimitIncludesExtensions` is off).
  The section's footer tells the player these limits.
- The built-in SideStore runs headless in LiveProcess, as an App Intent,
  through LiveContainer's SideStoreSupport (`performIntentRefresh`), which
  passes no parameters: an intent reads its request from the shared app
  group defaults and reports failures through the keychain item
  `cartouche.outcome` (patch 0014). LiveProcess reads the app group, not
  Cartouche's Documents: an IPA to install is copied there first.
- Installs, renewals and uninstalls need what Renew now needs: the setup
  done, LocalDevVPN connected, the pairing file in place. The section is
  disabled with the same message when they are not.
- SideStore's shared database, in the app group every SideStore of the same
  Apple ID opens, also lists that other store's apps. Cartouche keeps its
  own list of the bundle identifiers it installed, in the app group
  defaults, and every path below filters by it.
- iOS 17 or later, as every bridge action.

## Approaches

- **A. A System page section, Apps on this iPhone.** The list, Open, Renew,
  Uninstall and Install an IPA on this iPhone live under the signature and
  renewal they depend on. Import on the home keeps installing inside
  Cartouche. Chosen by the player (2026-11-13): the shelf stays one shelf of
  things that open in Cartouche (decision 86).
- **B. On the home shelf**, beside the apps installed inside Cartouche, with
  Import asking where each IPA goes. One place for every app, but a question
  on every import and a shelf that mixes apps that open in Cartouche with
  apps that leave it. Rejected.
- **C. Both**, a tile per outside app and the install on the System page.
  Dropped for the same reasons as B.

## Design, as decided

### SideStore, by a new patch (`app/patches/sidestore/0022-...`)

- **Cartouche's own apps.** The app group defaults hold
  `CartoucheInstalledApps`, the bundle identifiers of the apps Cartouche
  installed through SideStore (the identifier as installed, SideStore's
  `resignedBundleIdentifier` kept with the original). Patch 0017's two
  fetches, `fetchAppsForRefreshingAll` and `fetchAppsForBackgroundRefresh`,
  grow from "Cartouche alone" to "Cartouche and the active apps on that
  list": Renew now, the Shortcuts automation and SideStore's own background
  refresh then renew them together with Cartouche, and still nothing of
  another store's. 0017's commit message is amended, not contradicted.
- **Three intents**, written as `UpdateCartoucheIntent` is (patch 0010):
  `openAppWhenRun = false`, not discoverable, progress to 100, errors as
  `IntentError`, with `cartouche.outcome` written on the way out as 0014 has
  Sign In, Refresh and Update do, each with a kind of its own.
  - `CartoucheInstallAppIntent`: reads `CartoucheAppsRequest` from the app
    group defaults, the path of the IPA in the app group; runs
    `AppManager.shared.install(.url(ipa), presentingViewController: nil)`;
    on success adds the app's identifiers to `CartoucheInstalledApps`; in
    every case deletes the IPA copy. Prompts SideStore would show are
    answered by policy, never asked: extensions stay, as SideStore keeps
    them by default. Two checks come before anything goes to Apple, each a
    failure in Cartouche's own words through the outcome: an IPA whose
    bundle identifier the shared database already holds without being on
    `CartoucheInstalledApps` is refused, as an app another SideStore or
    AltStore installed and renews (the player of 2026-11-13 will never have
    one, so this guards other players; nothing is taken over); and an
    install that would pass the three active apps of a free Apple ID is
    refused, the count being every active free-team app in the shared
    database, Cartouche and another store's included, since SideStore only
    deactivates after the App ID is spent (`InstallAppOperation`). The
    weekly App ID limit stays Apple's answer, carried by the outcome.
  - `CartoucheRefreshAppsIntent`: reads the bundle identifiers from
    `CartoucheAppsRequest`, keeps those on `CartoucheInstalledApps`, and
    runs `AppManager.shared.refresh(apps, presentingViewController: nil)`.
    Renew now does not use it: it keeps running Refresh All Apps, which now
    covers these apps. Refresh All Apps renews every app at once and throws
    the first failure: the outcome grows per-app results, the identifier and
    the error's text of each app that failed, so that Renew now stays a
    success once Cartouche itself is renewed (`CartoucheFailure.renewalEnd`
    unchanged) and each failed app shows its failure under its row, a
    nightly one included, read at the next look at the section.
  - `CartoucheRemoveAppIntent`: one bundle identifier from
    `CartoucheAppsRequest`, on the list; `AppManager.shared.deleteApp`, which
    removes the app from the iPhone through minimuxer (LocalDevVPN on, as a
    renewal) and then SideStore's record; when the iPhone has no such app
    any more, an app deleted from the home screen, `removeApp` clears the
    record alone instead of failing. Either way the identifier leaves
    `CartoucheInstalledApps`.
- The widget data file `widget_data.json` keeps being SideStore's record of
  every installed app (name, identifier, expiry, last renewal), unchanged.

### LiveContainer's SideStoreSupport (`launcher/SideStoreSupport`)

- `CartoucheApps.swift`, an `@objc(CartoucheApps)` class beside
  `CartoucheRefresh`, with three class methods of the same shape as
  `refreshAllAppsWithProgress:completion:`: `installIPAWithProgress:completion:`,
  `refreshAppsWithProgress:completion:`, `removeAppWithProgress:completion:`.
  Each runs its intent through `performIntentRefresh` with the identifier
  and mangled type name of the intent. The request itself is in the app
  group defaults before the call, written by the launcher.

### The launcher (`launcher/Sources`)

- `CartoucheIPhoneApps.swift`: the model. Reads `CartoucheInstalledApps`
  from the app group defaults and joins it with `widget_data.json` (the
  decoding `CartoucheSignature` already has, widened to name and
  identifier) into rows: name, bundle identifier, expiry, days left, last
  renewal, and whether the signature is gone. Refreshes when Cartouche
  comes to the front and after each action. Runs the three bridge methods
  as `CartoucheRenewal.renew` runs its own: finds the class by its
  Objective-C name, a `Progress` to 100, failures as `CartoucheReport`s of a
  new origin with the SideStore outcome attached, telemetry events like a
  renewal's. Before an install, copies the picked IPA, under its
  security-scoped access, to the app group folder `Cartouche/Installs/`
  under a fresh name, and writes the request; removes any leftover there on
  start.
- `CartoucheIPhoneAppsView.swift`: the System page section **Apps on this
  iPhone**, under the signature and automatic renewal sections, with its
  page. The section shows the count and the soonest expiry, and opens the
  page; the page lists each app with its name, its **App ID** (the
  identifier SideStore registered it under with Apple, the bundle
  identifier with the team's appended for a free Apple ID, as SideStore's
  App IDs screen lists it), **Expires** and **Days left** as the signature
  section shows them (red once expired, orange at two days), **Renewed**,
  and the buttons **Open** (`sidestore-<identifier>://`
  through `UIApplication.open`, a failure saying the app is not on this
  iPhone any more), **Renew** and **Uninstall**, which asks first. Above the
  list, **Install an IPA on this iPhone** opens the Files picker on IPAs.
  One action at a time, its progress shown in its row as Renew now shows
  its own; a failure under the row with its report button. The footer says
  the limits: three apps with Cartouche, ten App IDs a week, signatures that
  Renew now and the nightly renewal keep alive, that the three count every
  app a free Apple ID signed on this iPhone, and that these apps open on
  the home screen, not in Cartouche. With imported signing the section
  shows the footer `signingUpdateOnComputer` says and nothing else; before
  the setup is done, the same message Renew now shows.
- **Renew now**, its footer and the nightly renewal's words in
  `CartoucheSystemView.swift` say "Cartouche and the apps it installed on this
  iPhone" where they say "Cartouche".
- Strings in English and French in `CartoucheText.swift` and
  `Cartouche.xcstrings`; Gallery stubs for the model and the bridge (a
  scenario with two apps, one expiring tomorrow); UI tests of the section,
  the page, Open, and the Uninstall question, in the Gallery as the other
  System pages have them; `app/tests` extended as the strings and UI-test
  words tests require, and a test that the new patch's intents and defaults
  keys match on both sides as `test_sidestore_outcome.py` checks the
  outcome's.

### Documents

- Decision 88, with 24 and 86 cross-referenced; decision 64 (SideStore renews
  Cartouche alone, patch 0017) amended: Cartouche and the apps it installed; `app/patches/README.md` for the new patch
  and 0017's wider scope; `launcher/README.md` for the section, the model
  and the bridge; `README.md` where it says what Cartouche does with IPAs
  that are not games; `docs/privacy.md` only if telemetry gains events,
  named as the renewal's are.

### Added the same day: the App IDs (`app/patches/sidestore/0023-...`)

- On the iPhone the first install was refused by Apple: *Your maximum App
  ID limit has been reached. You may create up to 10 App IDs every 7 days
  (9120)*, and the player asked to see the App IDs as SideStore's App IDs
  page lists them (name, expiry, Apple's identifier, bundle identifier).
- SideStore gets a fourth headless action, `CartoucheAppIDsIntent`, which
  fetches them from the developer portal as `SyncAppIDsOperation` does
  (`DeveloperPortalProxy.shared.fetchAppIDs()`, the session and the team
  from the keychain) and writes `Cartouche/AppIDs.json` in the app group:
  the date, and each App ID's name, identifier, bundle identifier and
  expiry, dates in seconds since 1970. Its outcome is the action `appIDs`.
- The bridge gains `fetchAppIDsWithProgress:completion:`; the model a
  `fetchAppIDs` action, the fourth kind of work, and the listing read from
  the file at each reload (`CartoucheIPhoneAppList.appIDs`, the one that
  expires first first, those without a date last); the page an **App IDs**
  section under the apps: **Fetch the App IDs from Apple**, then each App
  ID as SideStore's SwiftUI list shows it, with when and how many in the
  footer. Nothing is fetched on its own: a fetch is a sign-in to Apple.

## Left to the builder

- Exact predicate shapes in patch 0017's successor, the kinds added to
  `cartouche.outcome`, progress weights, the Gallery scenario's names.
- How the bundle identifier reaches the open URL when SideStore renamed it
  (`resignedBundleIdentifier`): the list keeps both and Open uses the
  resigned one.
- Whether a row for an app whose signature expired offers Open at all
  (iOS refuses to launch it): show the row, Open fails with the expired
  message, Renew is the way out.
- Icons: none in the widget data; the row shows a generic app symbol unless
  the install can keep the IPA's icon cheaply in the app group.
