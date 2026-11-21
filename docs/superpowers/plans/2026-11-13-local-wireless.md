# Local Wireless Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two or more iPhones (or iPads, or Macs running nxnative builds) on one Wi-Fi play a game's local wireless mode together, Mario Kart 8 Deluxe's Wireless Play first, from a **Local wireless** setting on the game's settings page that is off by default.

**Architecture:** nxnative answers `nn::ldn` and gives `nn::socket` real sockets through pull request #846 (ldn_mitm wire format, unicast subnet sweep for discovery, `DM_NETWORK=ldn`), carried by a fork branch `ldn` of nxnative that Cartouche Builder builds from until upstream merges; the setting is a row of nxnative's own settings list, which Cartouche's Game settings page already draws; Cartouche adds the local network prompt's words to the app and the game's process, and the documents.

**Tech Stack:** C (nxnative's host, `dm/host`), nxnative's `dm/games/settings.tsv` + `settings.py`, Bash (`app/scripts/package.sh`), Python `unittest` in `app/tests` and `builder/tests`, Swift/SwiftUI (gallery sample list only), two devices for the proof.

**Spec:** `docs/superpowers/specs/2026-11-13-local-wireless-design.md`

## Global Constraints

- No multicast entitlement, no paid team, no change to signing or installing (anti-goals). Discovery is #846's unicast sweep; `dm_net_set_multicast_allowed` stays off on iOS.
- The default is off: `DM_NETWORK` unset or `offline` opens no socket and asks no permission. Every test of the bridge runs with it on explicitly.
- Nothing of Nintendo's online, no server, no telemetry field that names a network or a peer (`docs/privacy.md` is amended to say what the local network is used for, nothing more).
- The fork `Hackiri/nxnative`, branch `ldn`, is upstream `main` + #846 rebased + one commit of ours (the settings row). Nothing else. Its commits are signed as hackiri (`commit.gpgsign` is on in this user's git config; a commit with another author fails on GPG).
- Cartouche's repository is `/Users/wm/orca/Cartouche`, branch `dev` (origin = `Hackiri/Cartouche`); `main` mirrors upstream and is never touched by this plan. The export `/Users/wm/orca/Cartouche-main` is refreshed from `dev` at the end (`git archive dev | tar -x -C …`).
- Strings: the prompt's texts live in `package.sh` (`LOCAL_NETWORK_EN`, `LOCAL_NETWORK_FR`), English apostrophes ’, French colons preceded by U+202F; no `CartoucheText` key is added unless Task 5 adds the sheet line.
- Decision numbers: this work is decision 143; 1 and 66 are cross-referenced, not amended.
- Commit messages in the project's voice; the attribution line the session reminder gives.

## Review Focus

1. **Which `Info.plist` iOS reads for the local network prompt when the game runs in `LiveProcess.appex`:** both carry the key (Task 3); the first run on an iPhone records which process asked and whether the prompt's text was ours (Task 7). If the extension's key is not read and the prompt shows LiveContainer's words or nothing, the fallback is to have Cartouche reach the local network once from its own process before the game starts (a one-shot `NWConnection` to the subnet's broadcast address is refused on iOS; a Bonjour browse of `_cartouche._tcp` is not), noted for a follow-up.
2. **The sweep on a Personal Hotspot:** `172.20.10.1/28` gives 14 hosts; `dm_net_discovery_subnet` requires 3 to 4094 hosts and a contiguous mask, so it passes; `t_net_discovery.c` gets a /28 case (Task 1) and the device proof includes a hotspot race (Task 7).
3. **A game whose version differs between the two devices:** LDN refuses with `LDN_VERSION_LOW/HIGH` and the game says no room was found; the getting-started section says "same version" (Task 6), not a Cartouche check: the sheet knows the build, not the other device's.
4. **Games with no local wireless** get the row too, since the list is per build from one `settings.tsv`: the row's note says what it does; whether `settings.py` can hide it per profile is checked in Task 2 and, if cheap (a profile key the generator already honours), done; else left in.
5. **The weekly rebuild** must take the fork's new commits: `engine_branch` = `ldn` is a branch the Builder fetches like `main`; `builder/tests` has a test that the engine's branch comes from the config (Task 4) so a hard-coded `main` cannot creep back.

---

### Task 1: The fork branch `ldn`: #846 rebased on upstream main

**Files:**
- Create: fork `https://github.com/Hackiri/nxnative.git` (`gh repo fork seedds/nxnative --clone=false`), branch `ldn`.
- Scratch clone: `/Users/wm/orca/nxnative` (durable, not the session scratchpad), remotes `origin` = the fork, `upstream` = `seedds/nxnative`.

**Interfaces:**
- Produces: branch `ldn` whose head builds the host tests and the iOS app; the commits of #846 (`gh pr checkout 846`, head `63fffb94…` or its current head) rebased on `upstream/main` of the day, recorded in the commit message of the merge or in `docs/decisions.md` row 143.

- [ ] **Step 1: Fork and clone.** `gh repo fork seedds/nxnative --clone=false`; `git clone https://github.com/Hackiri/nxnative.git /Users/wm/orca/nxnative`; `git remote add upstream https://github.com/seedds/nxnative.git`; `git fetch upstream`; `git fetch upstream pull/846/head:pr-846`.

- [ ] **Step 2: Rebase.** `git checkout -b ldn upstream/main`; `git rebase --onto ldn <merge-base of pr-846 and upstream/main> pr-846` into `ldn` (or `git cherry-pick` the PR's commits in order when the rebase's conflicts are only documentation, as #846's author found). Resolve: `docs/reference/services.md`'s symptom index is regenerated by nxnative's own script if it has one (check `scripts/`), else by hand where #846 inserted. Keep every source change of #846.

- [ ] **Step 3: Host tests.** In `dm/host`: `make -C tests` (or the Makefile target the README names) with `DM_NET_TEST`; expected: `t_ldn`, `t_ldn_events`, `t_net`, `t_net_discovery`, `t_discovery_protocol`, `t_net_write_prepare` pass, and every pre-existing test as before. Add to `t_net_discovery.c` a case for a /28 (`172.20.10.2`, mask `255.255.255.240`): 14 hosts, first `.1`, last `.14`, the local one skipped; expected PASS.

- [ ] **Step 4: iOS build smoke.** `scripts/build_ipa_from_nsp.py` needs a game; instead compile the iOS target alone as nxnative's `docs/development.md` describes (xcodegen on `dm/ios/project.yml`, `xcodebuild -sdk iphoneos CODE_SIGNING_ALLOWED=NO`), expected: `hle_ldn.c`, `hle_net_backend.c` compile for arm64 iOS with `TARGET_OS_IOS` and no warning above upstream's baseline (`.clang-tidy`).

- [ ] **Step 5: Push.** `git push -u origin ldn`. Record the upstream head and #846's head in `ldn`'s first commit of ours (Task 2) and in decision 143.

### Task 2: The settings row: `DM_NETWORK` on nxnative's list

**Files:**
- Modify (fork): `dm/games/settings.tsv`, regenerate `dm/launcher.json` outputs through `dm/games/settings.py` as nxnative does at build; `docs/settings.md` (a *Local wireless* section); `docs/env_switches.tsv` if #846 did not add `DM_NETWORK`, `DM_NET_DISCOVERY_PEER`, `DM_NET_TRACE` rows.

**Interfaces:**
- Produces, in every built app's `dm/launcher.json`: `{"env": "DM_NETWORK", "kind": "choice", "section": "Local wireless", "label": "Local wireless", "note": "…", "default": "offline", "options": [["offline", "Off"], ["ldn", "On this Wi-Fi"]]}` and `{"env": "DM_NET_TRACE", "kind": "toggle", "section": "Local wireless", "label": "Network trace", "note": "Logs the devices found and the packets, for a report.", "default": "0", "on": "1", "off": "0", "needs": "DM_NETWORK=ldn"}`.
- Consumed by: Cartouche's `CartoucheGameSettings.swift` (draws any section), nxnative's own iPhone settings screen and Mac window.

- [ ] **Step 1: Read `settings.tsv`'s columns and `settings.py`** (how `needs`, `options`, per-platform defaults and profile defaults are expressed; whether a profile can hide a row). Write the two rows in that form.

- [ ] **Step 2: Generate and validate.** Run `settings.py` the way `build_ipa.sh` runs it (see `docs/frontends.md`, *The settings list*); validate the output against `docs/launcher.schema.json` with Python's `jsonschema` if nxnative's tests do, else with a 10-line check that every required key is present and `needs` matches `^DM_[A-Z0-9_]+=[^;=]+$`. Expected: valid; the section order puts *Local wireless* after *Performance*.

- [ ] **Step 3: Documents in the fork.** `docs/settings.md`: a *Local wireless* section with the two rows, the sweep (no broadcast), the hotspot, client isolation, "same game, same version", and that ldn_mitm authenticates nothing. `docs/env_switches.tsv`: rows for the three switches if missing.

- [ ] **Step 4: Commit on `ldn`** (one commit: "Settings: Local wireless, DM_NETWORK and its trace on the list") and push. Then comment on upstream #846 with the row, the iOS findings and the link to `ldn`, offering it as a follow-up commit; no issue of our own, since #1175 is closed.

### Task 3: The local network prompt, for the app and the game's process

**Files:**
- Modify: `app/scripts/package.sh:80-96` (texts) and `:188-200` (LiveProcess keys)
- Modify: `app/tests/test_installed_build.py` or the test that reads `package.sh` today (find it with `grep -ln "NSLocalNetworkUsageDescription" app/tests`); if none, add `app/tests/test_local_network.py`.

**Interfaces:**
- Produces: `NSLocalNetworkUsageDescription` in `Payload/LiveContainer.app/Info.plist` and in `PlugIns/LiveProcess.appex/Info.plist`, English text: "Cartouche connects to Cartouche Builder on your Mac and to the shared folders of your Mac, PC or NAS on this network to keep your games and saves there, and lets a game with Local wireless on find the other players’ devices on it." French: "Cartouche se connecte à Cartouche Builder sur votre Mac et aux dossiers partagés de votre Mac, PC ou NAS sur ce réseau pour y garder vos jeux et vos sauvegardes, et laisse un jeu dont le Sans fil local est activé y trouver les appareils des autres joueurs." The French goes where the English one's French goes today (`fr.lproj/InfoPlist.strings`, see the loop after line 96).

- [ ] **Step 1: Write the test first.** The test reads `package.sh` and asserts: the two texts contain "Local wireless" / "Sans fil local"; the LiveProcess block sets `NSLocalNetworkUsageDescription` (a `plutil -replace NSLocalNetworkUsageDescription` or `$PB -c "Add :NSLocalNetworkUsageDescription …"` line between `LIVE_PROCESS=` and the `else`). Run: `python3 -m unittest discover -s app/tests -p 'test_local_network.py'`; expected: FAIL on both.

- [ ] **Step 2: Edit `package.sh`.** Texts as above; in the LiveProcess block, after the Game Mode keys: `plutil -replace NSLocalNetworkUsageDescription -string "$LOCAL_NETWORK_EN" "$LIVE_PROCESS"`, and the French in the extension's `fr.lproj/InfoPlist.strings` the same way the app's is written (create the lproj if the extension has none).

- [ ] **Step 3: Run the test**; expected PASS. Then a packaging dry run if the Mac has a built `work/` (`app/scripts/build.sh --prepared` after a build, or the next full build in Task 7); `plutil -p` both plists: the key is there with the new text.

- [ ] **Step 4: Commit** `app/scripts/package.sh app/tests/test_local_network.py`.

### Task 4: Cartouche Builder: the fork as the engine, documented and tested

**Files:**
- Modify: `builder/README.md` (*Settings* or the section that lists `config.json`'s keys; the row for `engine_url` / `engine_branch`)
- Modify: `builder/tests/test_config_state.py` (or the test of `Engine(paths.engine, config.engine_url, config.engine_branch)` in `batch.py:172`; add one if `engine_branch` is untested)

**Interfaces:**
- Consumes: `Config.engine_url`, `Config.engine_branch` (already there).

- [ ] **Step 1: Test.** A test that builds a `Config` with `engine_url="https://github.com/Hackiri/nxnative.git"`, `engine_branch="ldn"` and asserts the `Engine` the batch makes fetches that branch (whatever `Engine.__init__` stores: `self.branch`), and that `api.engine_info` reports the URL and branch (`api.py:245` has `"url": ctx.config.engine_url, "br…`). Run; expected: PASS already if the plumbing holds, FAIL if any path hard-codes `main`; fix the latter.

- [ ] **Step 2: README.** A paragraph under the config keys: "To play local wireless before nxnative merges it (pull request #846), set `engine_url` to `https://github.com/Hackiri/nxnative.git` and `engine_branch` to `ldn`: the branch is nxnative's `main` with #846 and the *Local wireless* setting; the weekly policy rebuilds your games from it. Set them back to the defaults once `main` has it."

- [ ] **Step 3: Run `python3 -m unittest discover -s builder/tests`**; expected: all pass. **Commit.**

### Task 5: The launcher: the gallery shows the section, the sheet says nothing new

**Files:**
- Modify: `launcher/Gallery/Sources/GalleryApp.swift` (the sample settings list `settings(for:entry:)` builds: add the two rows under section `Local wireless`)
- Modify: `launcher/Gallery/scenarios.json` (scenario `iphone-game-settings-wireless`: screen `settings`, `category` `Local wireless`, the usual iPhone frame)
- Modify: `launcher/Gallery/UITests/SettingsUITests.swift` or the settings UI test that exists (find with `grep -ln "game-settings" launcher/Gallery/UITests`): the section's title and the row's label appear; `needs` hides *Network trace* while *Off*, shows it once *On this Wi-Fi* is picked.
- Modify: `launcher/README.md:31` (Game settings: "a section the list adds, such as *Local wireless*, is drawn like the others").

**Interfaces:**
- Consumes: `CartoucheGameSettings.swift`'s reading of `launcher.json` (`kind` choice/toggle, `needs`): no change expected. If `needs` is not honoured for a row whose variable is a `choice` (check `CartoucheGameSettings.swift:546`, where a row is hidden), fix it here with a unit test in `launcher/Tests/CartoucheCoreTests` if the parsing is in `CartoucheCore`, else in the UI test.

- [ ] **Step 1: UI test first** (words from `CartoucheText` only where Cartouche owns them; the section and labels come from the sample list, so the test may name them directly). Run `xcodebuild test -project launcher/Gallery/CartoucheGallery.xcodeproj -scheme CartoucheGallery -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:…`; expected: FAIL, no such section.

- [ ] **Step 2: The sample rows and the scenario.** Add them; `launcher/Gallery/project.sh` is not needed (no new source file). Run the UI test; expected PASS. Capture the scenario with `launcher/Gallery/capture.sh` (cut the list to the scenario, `"language": "en"`, restore the file) and keep the PNG for the README's fork section if it reads well.

- [ ] **Step 3: `python3 -m unittest discover -s app/tests -p 'test_launcher_*.py'`**; expected PASS. **Commit.**

### Task 6: Documents and decision 143

**Files:**
- Modify: `docs/decisions.md` (row 143), `docs/roadmap.md` (*Next* and *Later*), `docs/getting-started.md` and `docs/getting-started.fr.md` (*Play together* / *Jouer ensemble*), `docs/privacy.md` (the local network paragraph), `README.md` (the fork's section: one bullet and, if captured, the settings picture), `docs/superpowers/specs/2026-11-13-local-wireless-design.md` (status line).

- [ ] **Step 1: Decision 143.** "Games play their local wireless mode between iPhones, iPads and Macs on one Wi-Fi, through nxnative's LDN bridge (pull request #846: `nn::ldn` in ldn_mitm's wire format, real sockets, a unicast sweep of the subnet for discovery, since iOS gives no broadcast to an app without Apple's multicast entitlement), carried by the fork branch `Hackiri/nxnative` `ldn` that Cartouche Builder builds from until upstream merges; off by default, one **Local wireless** setting per game on nxnative's own list, drawn by Game settings; the local network prompt names it, for the app and the game's process. No server, no online play (1), no measurement of it. Why: a player with two iPhones asked to race Mario Kart 8 Deluxe together (2026-11-13); the host is where every service answer lives; #846 had done the work and waited since 2026-11-01." Cross-reference 1 and 66.

- [ ] **Step 2: Roadmap, getting started, privacy, README, launcher README** as the spec's *Documents* says. Getting started's section: same Wi-Fi or one iPhone's Personal Hotspot; the setting on each device; the game's own Wireless Play menu; a guest network that isolates clients finds nothing; same game, same version, each from its own files.

- [ ] **Step 3: `python3 -m unittest discover -s app/tests`** (the documents tests, `test_brand`, `test_tree_digest`); expected PASS. **Commit.**

### Task 7: Build the games and the app, and prove it on two devices

**Files:**
- No source change expected; findings go into decision 143's row and the spec's status.

- [ ] **Step 1: Games.** On the Mac, Cartouche Builder with `engine_url`/`engine_branch` set to the fork: build Mario Kart 8 Deluxe 4.0.1 from the player's own files; install it on both devices from the games folder. Its sheet shows the build's commit as the fork's.

- [ ] **Step 2: The app.** `PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH" app/scripts/build.sh --out <scratchpad>/ipa-out` from `/Users/wm/orca/Cartouche` on `dev`; `plutil -p` both `Info.plist` files in the IPA: the new key and text; move the IPA to `build/app/Cartouche.ipa`, the previous kept beside it; install it on both devices with the Cartouche Installer (or Cartouche's own update, if a release is made).

- [ ] **Step 3: The race, on a home Wi-Fi.** On each device: Game settings › Local wireless › *On this Wi-Fi*. Start the game on both; iOS asks for the local network once per device (record which process asked, Review Focus 1). In the game: Wireless Play, one creates a room, the other finds it within the sweep's time and joins; a 50cc Grand Prix completes. Record: time to find the room, any desync or drop, the frame rate during the race (the Performance HUD setting), and the battery over the race.

- [ ] **Step 4: The race on a Personal Hotspot**, no router: one iPhone hosts, the other joins its Wi-Fi; repeat Step 3's room and one race.

- [ ] **Step 5: Failure cases, by hand.** The setting off on one device: the other finds no room. A guest network with client isolation, if one is at hand: no room, no crash. Network trace on: the report copied from Cartouche's console shows the sweep and the peers' addresses, nothing beyond the local network.

- [ ] **Step 6: Record and finish.** Decision 143's row gains the measured facts (which process asked, times, frame rate); the spec's status becomes "built"; `git archive dev | tar -x -C /Users/wm/orca/Cartouche-main`; push `dev`; a comment on upstream #846 with the two-device result.
