# Apps on this iPhone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cartouche installs an IPA as a normal iOS app through its built-in SideStore, lists the apps it installed that way with their expiry, opens, renews and uninstalls them, on its own screens.

**Architecture:** SideStore gains three headless App Intents (install, refresh, remove) and a list of the apps Cartouche installed, in the app group defaults, which patch 0017's two fetches also read so that Refresh All Apps renews Cartouche and those apps. LiveContainer's SideStoreSupport gets a `CartoucheApps` bridge shaped like `CartoucheRefresh`. The launcher gets a pure list model (tested on macOS), an observable model that runs the bridge and reads SideStore's outcome, and a System page section with its page.

**Tech Stack:** Swift 5 / SwiftUI (iOS 17+), AppIntents, patches on the pinned SideStore (ee3cc16a) applied by `app/scripts/prepare.sh`, Python `unittest` in `app/tests`, XCTest UI tests in `launcher/Gallery`, `swift test` for `CartoucheCore`.

**Spec:** `docs/superpowers/specs/2026-11-13-apps-on-this-iphone-design.md`

## Global Constraints

- iOS 17 or later for every bridge action; views `@available(iOS 17.0, *)` as the others.
- No SideStore page, prompt or toast reaches the player (decision 24): every intent runs with `presentingViewController: nil`, `openAppWhenRun = false`, `isDiscoverable { false }`.
- Only apps on `CartoucheInstalledApps` are listed, renewed, removed; an IPA whose bundle identifier the shared database holds without being on that list is refused.
- The three-app limit of a free Apple ID is checked before anything goes to Apple, counting every active free-team app in the shared database.
- Imported-signing mode (`CartoucheImportedSigning.accountSigningDisabled`): the section shows `CartoucheText.signingUpdateOnComputer` and nothing else.
- Strings: every new key in `CartoucheText.swift` has an entry in `Cartouche.xcstrings` in `en` and `fr`, `extractionState` manual, French colons preceded by U+202F; English apostrophes are ’. `python3 -m unittest discover -s app/tests -p 'test_launcher_*.py'` must stay green after each task that adds words.
- Decision numbers: this work is decision 137; decision 64 is amended, not contradicted.
- The checkout `/Users/wm/orca/Cartouche-main` has no `.git`. The scratch clone `/private/tmp/claude-501/-Users-wm-orca-Cartouche-main/c71335ee-0006-4d9a-8a07-2f86d1559fd4/scratchpad/upstream` (branch `local`, submodules fetched) is its git history: "commit" means copying the changed files there at the same paths and committing. Python tests that read submodules run there; tests that read the launcher alone run in either.
- Patches are authored against the pinned SideStore with the earlier patches applied: `scratchpad/ss-patched` is `ss-src` copied, `app/patches/sidestore/0001..0021` applied with `patch -s -N -t -p1`, then `git init && git add -A && git commit -q -m base`. A patch file is `git -C ss-patched format-patch -1 --stdout` with the subject and body written in the project's voice (see 0017's).
- Commit messages in the project's voice, one sentence of what and why; the attribution line the session reminder gives.

## Review Focus

1. **An IPA whose app the player deleted from the home screen but SideStore still lists**: Uninstall must clear it rather than fail; test in Task 2 (`CartoucheRemoveAppIntent` falls back to `removeApp` when minimuxer says the app is not installed).
2. **The widget data listing an app no longer on `CartoucheInstalledApps`, or the list naming an app the widget data lacks** (removed by another path, or not yet written): the row shows the name from the list with no dates, never a crash or a phantom; test in Task 4.
3. **An install picked while a renewal or an update is under way**: the bridge runs one intent at a time (`RefreshHandler`); the model refuses a second action with `CartoucheText.appsBusy` instead of queuing. No automated test reaches the bridge (the Gallery has none): the reviewer reads the guard at the top of each action in Task 4.
4. **The IPA copy left in `Cartouche/Installs/` by a Cartouche that was killed mid-install**: removed at the next reload; test in Task 4 (`testLeftoverIPAsOlderThanAnHourAreRemoved`).
5. **A nightly Refresh All Apps whose outcome names failed apps**: the failures show under the rows at the next look at the section and are consumed once; the split of the `failed` text is tested in Task 4 (`testFailedIdentifiersAreSplitOnCommas`), the single consumption by reading `reload()`: it removes the keychain item right after decoding.

---

### Task 1: Patch 0017 renews Cartouche and the apps it installed

**Files:**
- Modify: `app/patches/sidestore/0017-renew-cartouche-alone.patch` (regenerated)
- Modify: `app/tests/test_renewal.py:98-116`
- Modify: `app/patches/README.md:42`

**Interfaces:**
- Produces: the app group defaults key `CartoucheInstalledApps`, an array of dictionaries with the string keys `bundleIdentifier`, `resignedBundleIdentifier`, `name`; read in SideStore as `UserDefaults(suiteName: Bundle.Info.appGroups.first ?? "")?.array(forKey: "CartoucheInstalledApps") as? [[String: String]]`. Tasks 2 and 4 write and read the same shape.

- [ ] **Step 1: Change the test** in `app/tests/test_renewal.py`, `test_the_built_in_sidestore_renews_cartouche_alone`, keeping its name: for each of the two functions the body must contain `InstalledApp.fetchAltStore(in: context)` and `"CartoucheInstalledApps"`, and must not contain `storeApp` (no pledge predicate, no other store's apps). Update the docstring line 10 to "renews Cartouche and the apps Cartouche installed".

- [ ] **Step 2: Run it to see it fail**

Run, in the scratch clone: `python3 -m unittest test_renewal -k renews_cartouche_alone` from `app/tests` (or `python3 -m unittest discover -s app/tests -p 'test_renewal.py'`)
Expected: FAIL, `"CartoucheInstalledApps"` not found.

- [ ] **Step 3: Regenerate the patch.** In `ss-patched`, with 0001..0016 applied and committed as base, apply 0017, then edit `AltStore/Core/Model/InstalledApp.swift` so both functions build `installedApps` from a predicate `isActive == YES AND bundleIdentifier IN %@` over the identifiers of `CartoucheInstalledApps` (empty list: no fetch), sorted by `expirationDate`, then add Cartouche as the current patch does; `fetchAppsForBackgroundRefresh` keeps its six-hour `refreshedDate` condition on those apps too. Comment in the project's voice: why the other store's apps stay out, why Cartouche's own list is the line. Produce the patch with `git format-patch` against base, keep the file name, subject "Renew Cartouche and the apps it installed alone", body amended from 0017's.

- [ ] **Step 4: Run the tests**

Run: `python3 -m unittest discover -s app/tests -p 'test_renewal.py'` in the scratch clone
Expected: the two 0017 tests pass; the others as before.

- [ ] **Step 5: Amend `app/patches/README.md` row 42**: "renew Cartouche and the apps Cartouche installed on this iPhone (`CartoucheInstalledApps`, decision 137), never the apps of another SideStore of the same Apple ID".

- [ ] **Step 6: Commit** `app/patches/sidestore/0017-renew-cartouche-alone.patch app/tests/test_renewal.py app/patches/README.md`.

### Task 2: Patch 0026, SideStore's three intents and the outcome's new actions

**Files:**
- Create: `app/patches/sidestore/0026-install-renew-and-remove-apps-for-cartouche.patch`, adding `SideStore/Intents/CartoucheInstallAppIntent.swift`, `SideStore/Intents/CartoucheRefreshAppsIntent.swift`, `SideStore/Intents/CartoucheRemoveAppIntent.swift`, `SideStore/Intents/CartoucheAppsRequest.swift`; modifying `SideStore/Intents/CartoucheOutcome.swift` and `AltStore/Intents/App Intents/RefreshAllAppsIntent.swift`
- Create: `app/tests/test_iphone_apps.py`
- Modify: `app/tests/test_sidestore_outcome.py:255-275`
- Modify: `app/patches/README.md` (new row after 0025)

**Interfaces:**
- Consumes: `CartoucheInstalledApps` (Task 1); `CartoucheOutcome(action:)`, `.note(_:_:)`, `.save(error:stage:progress:)` (patch 0014).
- Produces:
  - app group defaults key `CartoucheAppsRequest`, a dictionary: `["ipa": String]` (path under the app group) for the install, `["apps": [String]]` (bundle identifiers) for the refresh, `["app": String]` for the removal; the intent removes the key when done.
  - `CartoucheOutcome.Action` cases `install`, `apps`, `remove`; outcome key `failed`, a text, the bundle identifiers that failed joined by `,`, written by `CartoucheRefreshAppsIntent` and by `RefreshAllAppsIntent` (0014's outcome of action `refresh`) when some app failed.
  - `enum CartoucheAppsError: LocalizedError { case noRequest, anotherStoresApp(String), appLimit(Int), notListed(String) }` in `CartoucheAppsRequest.swift`, mapped by `CartoucheOutcome.kind(of:)` to family `"cartouche"` and its case name, as `CartoucheSignInError` is.
  - Intent type names, for the bridge: `CartoucheInstallAppIntent` (`9SideStore25CartoucheInstallAppIntentV`), `CartoucheRefreshAppsIntent` (`9SideStore26CartoucheRefreshAppsIntentV`), `CartoucheRemoveAppIntent` (`9SideStore24CartoucheRemoveAppIntentV`).

- [ ] **Step 1: Write `app/tests/test_iphone_apps.py`** (reads the patch's added files as `test_update.py`'s `added_by_patch` does, and the bridge and launcher files Tasks 3 and 4 create; the bridge and launcher assertions fail until then, which is expected):
  - `test_the_patch_adds_the_three_intents`: the patch adds `struct CartoucheInstallAppIntent: AppIntent`, `struct CartoucheRefreshAppsIntent: AppIntent`, `struct CartoucheRemoveAppIntent: AppIntent`, each with `static var openAppWhenRun = false` and `static var isDiscoverable: Bool { false }`, `presentingViewController: nil` on every `AppManager.shared.` call, and no other `presentingViewController:` value.
  - `test_the_intents_read_the_request_and_the_list_cartouche_writes`: the strings `"CartoucheAppsRequest"` and `"CartoucheInstalledApps"` appear in the patch and in `launcher/Sources/CartoucheIPhoneApps.swift`; the request's keys `"ipa"`, `"apps"`, `"app"` appear in both.
  - `test_the_install_refuses_another_stores_app_and_the_app_limit_before_apple`: in `CartoucheInstallAppIntent.swift`, `anotherStoresApp` and `appLimit` are thrown before the text `AppManager.shared.install(`.
  - `test_the_removal_clears_an_app_that_is_gone`: `CartoucheRemoveAppIntent.swift` calls `deleteApp(` and, in a catch, `removeApp(`.
  - `test_the_bridge_runs_the_three_intents`: `launcher/SideStoreSupport/CartoucheApps.swift` has `@objc(CartoucheApps)`, selectors `installAppWithProgress:completion:`, `refreshAppsWithProgress:completion:`, `removeAppWithProgress:completion:`, and three `performIntentRefresh(identifier:mangledTypeName:)` calls whose identifiers are the three intent names and whose mangled names are `f"{len('SideStore')}SideStore{len(name)}{name}V"`.
  - `test_the_launcher_finds_the_bridge_by_its_names`: `CartoucheIPhoneApps.swift` has `NSClassFromString("CartoucheApps")` and the three selectors.

- [ ] **Step 2: Run it to see it fail**

Run: `python3 -m unittest discover -s app/tests -p 'test_iphone_apps.py'`
Expected: every test FAILS (no patch 0026, no bridge, no model).

- [ ] **Step 3: Extend `test_sidestore_outcome.py`**: actions set becomes `{"signIn", "device", "refresh", "update", "install", "apps", "remove"}`; `left` gains the three intent files with their actions; `waited` gains `"CartoucheIPhoneApps.swift": ["install", "apps", "remove"]`; nothing else.

- [ ] **Step 4: Write the patch** in `ss-patched` (0001..0021 applied, committed as base):
  - `CartoucheAppsRequest.swift`: `enum CartoucheAppsRequest` with `static func take() -> [String: Any]?` (reads and removes `CartoucheAppsRequest` from the app group defaults), `static var installed: [[String: String]]` get/set over `CartoucheInstalledApps`, and `CartoucheAppsError`.
  - `CartoucheInstallAppIntent`: outcome `CartoucheOutcome(action: .install)`; `DatabaseManager.shared.start()`; request path or `noRequest`; `defer` removing the IPA file; reads the bundle identifier as `AppManager.readAppMetadata` does (or `AnyApp` through `resolveApp`, whichever is reachable); on the view context, if an `InstalledApp` with that identifier exists and is not on `installed`, throw `anotherStoresApp(name)`; if `UserDefaults.standard.activeAppsLimit` is set and the active free-team apps' `requiredActiveSlots` plus one exceed it, throw `appLimit(limit)`; then `AppManager.shared.install(.url(ipa), presentingViewController: nil)` with its progress as a child of the intent's (95 units); on success append `[bundleIdentifier, resignedBundleIdentifier, name]` to `installed`; `outcome.save` in both paths, `IntentError` on failure, as `UpdateCartoucheIntent`.
  - `CartoucheRefreshAppsIntent`: action `.apps`; the request's `apps` filtered by `installed`; `InstalledApp`s fetched by identifier on a background context; `AppManager.shared.refresh(apps, presentingViewController: nil)`, result per app; `outcome.note("failed", ids.joined(","))` when some failed, then throw the first error.
  - `CartoucheRemoveAppIntent`: action `.remove`; the one `app`, must be on `installed` else `notListed`; `deleteApp`; in the catch, when the error is minimuxer's for an app not installed (read `UninstallAppOperation.swift` and `MinimuxerError` for the case), `removeApp` instead; either way take the identifier off `installed`.
  - `CartoucheOutcome.swift`: the three `Action` cases; `kind(of:)` maps `CartoucheAppsError`.
  - `RefreshAllAppsIntent.swift` (as 0014 left it): collect the identifiers whose result failed and `outcome.note("failed", ...)` before the first error is thrown.
  - Commit in `ss-patched`, `git format-patch -1 --stdout > app/patches/sidestore/0026-install-renew-and-remove-apps-for-cartouche.patch`, subject "Install, renew and remove apps on the iPhone for Cartouche".

- [ ] **Step 5: Check the patch applies on the pristine chain**: in a fresh copy of `ss-src` apply 0001..0022 with `patch -s -N -t -p1`; expected no rejects.

- [ ] **Step 6: Run the Python tests**

Run, in the scratch clone after syncing: `python3 -m unittest discover -s app/tests -p 'test_sidestore_outcome.py'` and `-p 'test_iphone_apps.py'`
Expected: `test_sidestore_outcome` passes; in `test_iphone_apps` only the bridge and launcher tests still fail.

- [ ] **Step 7: Add the row to `app/patches/README.md`** after 0025, in the table's voice: what the three intents do, that Cartouche's screens run them headless, decision 137.

- [ ] **Step 8: Commit** the patch, the two test files and the README.

### Task 3: The bridge, `CartoucheApps` in SideStoreSupport

**Files:**
- Create: `launcher/SideStoreSupport/CartoucheApps.swift`

**Interfaces:**
- Consumes: `performIntentRefresh(identifier:mangledTypeName:intentProgress:)` (LiveContainer's `SideStoreSupport/SideStore.swift`); intent names of Task 2.
- Produces: `@objc(CartoucheApps) public final class CartoucheApps: NSObject` with `@objc(installAppWithProgress:completion:) public static func installApp(progress: Progress, completion: @escaping (String?) -> Void)`, `@objc(refreshAppsWithProgress:completion:) public static func refreshApps(...)`, `@objc(removeAppWithProgress:completion:) public static func removeApp(...)`; each `guard #available(iOS 17.0, *)`, `Task { @MainActor in ... }`, completion with nil or `error.localizedDescription`, as `CartoucheRefresh.refreshAllApps`.

- [ ] **Step 1: Write the file**, header comment in the project's voice (the request is in the app group before the call; one action at a time, the bridge's `RefreshHandler` allowing one).

- [ ] **Step 2: Run the test**

Run: `python3 -m unittest discover -s app/tests -p 'test_iphone_apps.py' -k bridge`
Expected: `test_the_bridge_runs_the_three_intents` PASS.

- [ ] **Step 3: Commit** `launcher/SideStoreSupport/CartoucheApps.swift`.

### Task 4: The launcher's models: the pure list and the observable model

**Files:**
- Create: `launcher/Sources/CartoucheIPhoneAppList.swift` (pure Foundation)
- Create: `launcher/Tests/CartoucheCoreTests/CartoucheIPhoneAppListTests.swift`
- Modify: `launcher/Package.swift:26` (add `"CartoucheIPhoneAppList.swift"` to `sources`)
- Create: `launcher/Sources/CartoucheIPhoneApps.swift`
- Modify: `launcher/Sources/CartoucheReport.swift:51-67` (`Origin` gains `case apps` with a doc comment)
- Modify: `launcher/Sources/CartoucheFailure.swift:444-500` (`Action` gains `install`, `apps`, `remove`; `Written.Key` gains `failed`, read as a text; `cause` maps family `"cartouche"` kinds `anotherStoresApp`, `appLimit`, `notListed`, `noRequest` to new `Cause` cases `anotherStore`, `appLimit`, `appNotListed`, `noRequest`)
- Modify: `launcher/Sources/CartoucheRenewal.swift:64-72` (after the outcome is read, `CartoucheIPhoneApps.shared.noteRenewal(outcome: outcome, message: message)`)
- Modify: `launcher/Sources/CartoucheText.swift` (new MARK "Apps on this iPhone (decision 137)"), `launcher/Sources/Cartouche.xcstrings`

**Interfaces:**
- Consumes: Task 1's list shape, Task 2's request shape, outcome actions and `failed` key, Task 3's bridge names; `LCUtils.appGroupUserDefault`, `LCSharedUtils.appGroupPath()`, `CartoucheStoreKeychain`, `CartoucheSideStoreOutcome(data:expecting:)`, `CartoucheFailure.sideStore(...)`, `CartoucheReports.make(...)`, `CartoucheVPN.isConnected`, `CartouchePairing.exists`, `CartoucheImportedSigning.accountSigningDisabled`.
- Produces:
  ```swift
  struct CartoucheIPhoneApp: Identifiable, Equatable, Sendable {
      let name: String, bundleIdentifier: String, resignedBundleIdentifier: String
      let expirationDate: Date?, refreshedDate: Date?
      var id: String { bundleIdentifier }
      var daysLeft: Int?            // whole days, 0 on the last day, negative once expired, nil without a date
      var isExpired: Bool
      var openURL: URL              // "sidestore-<resignedBundleIdentifier>://"
  }
  enum CartoucheIPhoneAppList {
      static func apps(listed: [[String: String]], widgetData: Data?, now: Date = Date()) -> [CartoucheIPhoneApp]
      static func soonestExpiry(of apps: [CartoucheIPhoneApp]) -> Date?
  }
  @MainActor final class CartoucheIPhoneApps: ObservableObject {
      static let shared: CartoucheIPhoneApps
      struct Work: Equatable { enum Kind: Equatable { case installing(String), renewing(String), removing(String) }; let kind: Kind; let progress: Progress }
      @Published private(set) var apps: [CartoucheIPhoneApp]
      @Published private(set) var work: Work?
      @Published private(set) var failures: [String: CartoucheReport]   // by bundle identifier; "" for the last install
      static var isAvailable: Bool          // bridge found and !accountSigningDisabled
      static var unavailableReason: String? // signingUpdateOnComputer, or renewUnavailable
      func reload()                         // list + widget data + leftover outcome; removes stale IPA copies
      func install(ipa: URL) async          // copies under security scope to <app group>/Cartouche/Installs/<UUID>.ipa, writes the request, runs the bridge
      func renew(_ app: CartoucheIPhoneApp) async
      func remove(_ app: CartoucheIPhoneApp) async
      func open(_ app: CartoucheIPhoneApp) async -> Bool
      func noteRenewal(outcome: CartoucheSideStoreOutcome?, message: String?)
  }
  ```
  Strings (keys, English): `system.apps.title` "Apps on this iPhone"; `system.apps.none` "None yet"; `system.apps.count` "%lld apps, the first expires in %lld days" plus `system.apps.count.one` "1 app, expires in %lld days" (pick the form by count); `system.apps.install` "Install an IPA on this iPhone"; `system.apps.installing` "Installing %@"; `system.apps.renewing` "Renewing %@"; `system.apps.removing` "Uninstalling %@"; `system.apps.renew` "Renew"; `system.apps.uninstall.question` "Uninstall %@ from this iPhone?"; `system.apps.uninstall.confirm` "Uninstall"; `system.apps.open.failed` "%@ is not on this iPhone any more: renew it, or uninstall it here."; `system.apps.busy` "Wait for the step under way to finish."; `system.apps.failed.install` "The app did not install"; `system.apps.failed.renew` "%@ was not renewed"; `system.apps.failed.remove` "%@ was not uninstalled"; `system.apps.error.anotherStore` "Another SideStore or AltStore installed this app and renews it: Cartouche leaves it alone."; `system.apps.error.limit` "A free Apple ID signs three apps at once on this iPhone, Cartouche included. Uninstall one first."; `system.apps.footer` "Cartouche installs them with the Apple ID it signs with, as its own app on the home screen, and renews them with itself: Renew now and the nightly renewal keep their signatures alive. A free Apple ID signs three apps at once on this iPhone, Cartouche and any app signed by another store included, and ten App IDs a week."; `system.apps.footer.imported` reuse `signingUpdateOnComputer`. Existing `signatureFooter` and `daily.intro` gain "and the apps it installed on this iPhone".

- [ ] **Step 1: Write `CartoucheIPhoneAppListTests.swift`**:
  - `testAppsJoinTheListWithTheWidgetDataByIdentifier`: two listed apps, widget data (JSON of `{"activeApps":[],"allApps":[...],"lastUpdated":...}` with dates as seconds since 2001) holding one of them plus a third app not listed: the result has the two listed apps in list order, the first with its dates and `daysLeft == 3` for an expiry 3.5 days after `now`, the second with nil dates, and no third app.
  - `testDaysLeftIsZeroOnTheLastDayAndNegativeOnceExpired`.
  - `testTheOpenURLUsesTheResignedIdentifier`: `openURL.absoluteString == "sidestore-com.utmapp.UTM.ABCDE12345://"`.
  - `testSoonestExpiryIgnoresAppsWithoutADate`.
  - `testBrokenWidgetDataLeavesTheListWithoutDates` (data `"{"`).
  - `testLeftoverIPAsOlderThanAnHourAreRemoved`: `CartoucheIPhoneAppList.removeLeftoverIPAs(in folder: URL, olderThan age: TimeInterval = 3600, now: Date = Date())` removes a file dated two hours before `now` and keeps one dated ten minutes before, in a temporary folder.
  - `testFailedIdentifiersAreSplitOnCommas`: `CartoucheIPhoneAppList.failedIdentifiers("a.b, c.d,,") == ["a.b", "c.d"]` and `failedIdentifiers(nil) == []`.

- [ ] **Step 2: Run them to see them fail**

Run: `cd launcher && PATH=/usr/bin:/bin:$PATH swift test --filter CartoucheIPhoneAppListTests`
Expected: compile failure, `CartoucheIPhoneAppList` not found.

- [ ] **Step 3: Write `CartoucheIPhoneAppList.swift`** and add it to `Package.swift`; decode the widget data with the `WidgetData` shape `CartoucheSignature` has, widened to `name`.

- [ ] **Step 4: Run them to see them pass**

Run: `cd launcher && PATH=/usr/bin:/bin:$PATH swift test --filter CartoucheIPhoneAppListTests`
Expected: 5 tests pass.

- [ ] **Step 5: Write `CartoucheIPhoneApps.swift`** with the interface above; `reload()` also takes a leftover `.refresh` outcome at most 24 hours old whose `failed` names listed apps, turns each into a `failures` entry (title `appsFailedRenew(name)`, report origin `.apps`, failure from `CartoucheFailure.sideStore`), and removes the keychain item; each action: `guard work == nil else { failures[...] = busy }`, `CartoucheStoreKeychain.remove(CartoucheSideStoreOutcome.account)`, write `CartoucheAppsRequest`, call the bridge method by its selector with `unsafeBitCast` as `CartoucheRenewal.refreshAllApps` does, read the outcome with the matching `expecting:`, on failure a `CartoucheReport` of origin `.apps`, then `reload()`.

- [ ] **Step 6: Add the strings, the `Origin` case, the outcome's actions and key, the causes, and the `CartoucheRenewal` call.** Run the strings tests.

Run: `python3 -m unittest discover -s app/tests -p 'test_launcher_*.py'` and `-p 'test_sidestore_outcome.py'` (scratch clone) and `-p 'test_iphone_apps.py'`
Expected: all pass.

- [ ] **Step 7: Build the Gallery** (compiles the launcher sources with the stubs): `cd launcher/Gallery && xcodebuild build-for-testing -quiet -project CartoucheGallery.xcodeproj -scheme CartoucheGallery -destination 'platform=iOS Simulator,id=A20996C7-73E0-455F-8199-C1FF24C01BC7' -derivedDataPath <scratchpad>/gallery-dd`
Expected: EXIT 0, no `error:` lines. If the Gallery lacks a stub the model needs, add it to `GalleryStubs.swift` in the file's style.

- [ ] **Step 8: Commit** the two sources, the test, `Package.swift`, `CartoucheReport.swift`, `CartoucheFailure.swift`, `CartoucheRenewal.swift`, `CartoucheText.swift`, `Cartouche.xcstrings`.

### Task 5: The System page section and the Apps on this iPhone page

**Files:**
- Create: `launcher/Sources/CartoucheIPhoneAppsView.swift`
- Modify: `launcher/Sources/CartoucheSystemView.swift:45-55` (`iphoneAppsSection` after `automaticRenewalSection`, outside the imported-signing condition)
- Modify: `launcher/Gallery/Sources/GalleryApp.swift` (scenario option `iphoneApps`, `-GalleryIPhoneApps`, "Name:bundle.id:daysLeft"), `launcher/Gallery/UITests/ConsoleTestCase.swift` (`Launch.iphoneApps`, `Words`), `launcher/Gallery/UITests/SystemUITests.swift`, `launcher/Gallery/scenarios.json` (one scenario `iphone-system-apps` for the screenshots)

**Interfaces:**
- Consumes: `CartoucheIPhoneApps.shared`, `CartoucheIPhoneApps.isAvailable`, strings of Task 4, `CartoucheReportButton`, `cartoucheStageBackground()`, the `renewRow` pattern of `CartoucheSystemView`.
- Produces: `struct CartoucheIPhoneAppsSection: View` (the row for the System page: title, subtitle count or none, `NavigationLink` to the page; in imported-signing mode the footer alone) and `struct CartoucheIPhoneAppsView: View` (the page).

- [ ] **Step 1: Add the words** to `Words` in `ConsoleTestCase.swift`: `iphoneApps = "Apps on this iPhone" // system.apps.title`, `installOnIPhone = "Install an IPA on this iPhone" // system.apps.install`, `renewApp = "Renew" // system.apps.renew`, `uninstallFromIPhone = "Uninstall %@ from this iPhone?" // system.apps.uninstall.question`, `daysLeft` if absent (`// system.signature.daysLeft`, check the key). Add `var iphoneApps: [String] = []` to `Launch` and `-GalleryIPhoneApps`.

- [ ] **Step 2: Write the UI tests** in `SystemUITests.swift`: add `(Words.iphoneApps, Words.installOnIPhone)` to `pages`; add `testAppsOnThisIPhoneListsEachAppAndAsksBeforeUninstalling` with `Launch(iphoneApps: ["UTM:com.utmapp.UTM:3", "Delta:com.rileytestut.Delta:0"])`: System, the row, the page; both names present; `Words.daysLeft` rows present; the Uninstall button of UTM (`element(in: app.buttons, beginningWith: Words.uninstall)` first) opens an alert titled `String(format: Words.uninstallFromIPhone, "UTM")`; Cancel closes it; `expectMainThreadAnswered`.

- [ ] **Step 3: Run the strings-words test to see it fail**

Run: `python3 -m unittest discover -s app/tests -p 'test_launcher_ui_tests.py'`
Expected: FAIL for the new words until the strings exist (they exist from Task 4: expected PASS then; the UI test itself cannot run yet).

- [ ] **Step 4: Write the view**: the section row and the page as the spec says (rows with name, **Expires**, **Days left** coloured as the signature section, **Renewed**, buttons Open, Renew, Uninstall with a confirmation alert; above, **Install an IPA on this iPhone** with `.fileImporter(allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data, .data])`, disabled while `work != nil`; the work's progress in its row with `TimelineView(.periodic(from: .now, by: 0.5))` as `renewRow`; a failure under the row with `CartoucheReportButton`; the footer). `.task { model.reload() }` and `onReceive(UIApplication.didBecomeActiveNotification)` reload. Wire the section into `CartoucheSystemView`.

- [ ] **Step 5: Seed the gallery**: `GalleryScenario.iphoneApps`, parsed from `-GalleryIPhoneApps`; in `prepare()` (where the stand-ins' files are put), write `CartoucheInstalledApps` to `UserDefaults.standard` and `widget_data.json` to `GalleryState.appGroup` with `JSONEncoder()` default dates, `expirationDate = now + days*86400 + 43200`, `refreshedDate = now - 86400`; add the scenario `iphone-system-apps` (screen `system`, two apps) to `scenarios.json`.

- [ ] **Step 6: Build and run the two System UI tests**

Run: build-for-testing as in Task 4, then `xcodebuild test-without-building ... -only-testing:CartoucheGalleryUITests/SystemUITests -parallel-testing-enabled NO`
Expected: both pass (the main-thread watch included; run on an otherwise idle Mac).

- [ ] **Step 7: Run the Python tests** `-p 'test_launcher_*.py'`: pass.

- [ ] **Step 8: Commit** the view, `CartoucheSystemView.swift`, the Gallery files, the UI tests.

### Task 6: Documents and decision 137

**Files:**
- Modify: `docs/decisions.md` (row 64 amended; row 137 added after 136), `launcher/README.md` (the System page's bullets: a bullet for Apps on this iPhone naming the model, the view, the bridge, the patch; Renew now's words), `README.md:36` (one sentence: an IPA can also be installed on the iPhone itself, outside Cartouche, from the System page), `docs/superpowers/specs/2026-11-13-apps-on-this-iphone-design.md` (status: built)

- [ ] **Step 1: Write decision 137** in the table's voice: what (the section, the intents, the list, 0017 widened, the two refusals, Uninstall through `deleteApp`, per-app failures), why (the player's ask of 2026-11-13, no standalone SideStore for them, decision 24 kept, 64's reason kept by the list), cross-references to 24, 64, 86, the patch files and the three launcher files. Amend 64: "Amended by 137: Cartouche and the apps Cartouche itself installed on this iPhone".

- [ ] **Step 2: Update the READMEs** as listed.

- [ ] **Step 3: Run** `python3 -m unittest discover -s app/tests` in the scratch clone: the same 25 pre-existing submodule failures or fewer, none new (compare against `scratchpad/fail-merged.txt`).

- [ ] **Step 4: Commit** the documents.

### Task 7: Build the app and prove the whole

**Files:** none new.

- [ ] **Step 1: Full Python suite** in the scratch clone (submodules present): `python3 -m unittest discover -s app/tests`; expected: all pass apart from none (the submodule-bound tests pass there).

- [ ] **Step 2: Build the IPA**: in the scratch clone, `PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" app/scripts/build.sh --out <scratchpad>/ipa-out2`; expected `BUILD EXIT=0`, the SideStore step compiling the three intents and the LiveContainer step the bridge; `unzip -Z1` lists `SideStoreApp.framework` and `SideStoreSupport.framework`.

- [ ] **Step 3: Gallery UI tests** for Apps and System on the iPhone 17 simulator: pass.

- [ ] **Step 4: Put the IPA in place**: `build/app/Cartouche.ipa`, the previous kept as `Cartouche-0.12.0-previous.ipa`.

- [ ] **Step 5: Commit** and sync: every tracked file of the scratch clone matches the checkout (the hash check used after the merge).
