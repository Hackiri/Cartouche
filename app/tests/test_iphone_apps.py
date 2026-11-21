"""Checks that the apps Cartouche installs on this iPhone through the built-in
SideStore (app/patches/sidestore/0027 and 0028, decision 137) line up across
the three sides that make them work:

- the patches add the four actions, install, refresh, remove and the list
  of the App IDs, headless: no page of SideStore's, no prompt, not listed
  by Shortcuts;
- they read the request and keep the list Cartouche writes in the app
  group, under the names the launcher writes them by;
- the install refuses another store's app and the three-app limit before
  anything goes to Apple, and the removal clears an app that is already
  gone from the home screen;
- CartoucheApps (launcher/SideStoreSupport) runs the four actions by
  their types' mangled names, and the launcher finds it by its
  Objective-C names.

Run from the repository root: python3 -m unittest discover -s app/tests -v
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PATCHES = ROOT / "app" / "patches" / "sidestore"
BRIDGE = ROOT / "launcher" / "SideStoreSupport" / "CartoucheApps.swift"
LAUNCHER = ROOT / "launcher" / "Sources" / "CartoucheIPhoneApps.swift"
MODULE = "SideStore"
INTENTS = ("CartoucheInstallAppIntent", "CartoucheRefreshAppsIntent", "CartoucheRemoveAppIntent",
           "CartoucheAppIDsIntent")
SELECTORS = ("installAppWithProgress:completion:", "refreshAppsWithProgress:completion:",
             "removeAppWithProgress:completion:", "fetchAppIDsWithProgress:completion:")
PATCH_NAMES = ("*-install-renew-and-remove-apps-for-cartouche.patch", "*-list-the-app-ids-for-cartouche.patch")


def apps_patches() -> list:
    found = []
    for name in PATCH_NAMES:
        patches = sorted(PATCHES.glob(name))
        if len(patches) != 1:
            raise AssertionError(f"expected one {name} in {PATCHES.relative_to(ROOT)}, found {len(patches)}")
        found.append(patches[0])
    return found


def added_files() -> dict:
    """The lines patches 0027 and 0028 add, by the file they go to."""
    files, current = {}, None
    for patch in apps_patches():
        for line in patch.read_text(encoding="utf-8").splitlines():
            if line.startswith("+++ b/"):
                current = line[6:].strip()
                files.setdefault(current, [])
            elif line.startswith("+") and not line.startswith("+++") and current:
                files[current].append(line[1:])
    return {name: "\n".join(lines) for name, lines in files.items()}


def read(path: Path) -> str:
    if not path.exists():
        raise AssertionError(f"{path.relative_to(ROOT)} is missing")
    return path.read_text(encoding="utf-8")


class IPhoneAppsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.added = added_files()
        cls.intents = {name: cls.added[f"{MODULE}/Intents/{name}.swift"] for name in INTENTS}
        cls.patch = "\n".join(cls.added.values())

    def test_the_patches_add_the_four_intents(self):
        for name, text in self.intents.items():
            with self.subTest(intent=name):
                self.assertIn(f"struct {name}: AppIntent", text)
                self.assertIn("static var openAppWhenRun = false", text)
                self.assertIn("static var isDiscoverable: Bool { false }", text)
                # Every call into SideStore is headless: the App IDs come
                # from the developer portal as SyncAppIDsOperation gets them.
                calls = re.findall(r"AppManager\.shared\.\w+\((?:[^()]|\([^()]*\))*\)", text, re.S)
                if name == "CartoucheAppIDsIntent":
                    self.assertIn("DeveloperPortalProxy.shared.fetchAppIDs()", text)
                    self.assertEqual(calls, [])
                else:
                    self.assertTrue(calls, "no AppManager call")
                for call in calls:
                    if "presentingViewController" in call:
                        self.assertIn("presentingViewController: nil", call, call)
                self.assertLessEqual(set(re.findall(r"presentingViewController: (\w+)", text)), {"nil"})

    def test_the_intents_read_the_request_and_the_list_cartouche_writes(self):
        launcher = read(LAUNCHER)
        for name in ('"CartoucheAppsRequest"', '"CartoucheInstalledApps"', '"ipa"', '"apps"', '"app"',
                     '"Cartouche/AppIDs.json"'):
            with self.subTest(name=name):
                self.assertIn(name, self.patch)
                self.assertIn(name, launcher)

    def test_the_install_refuses_another_stores_app_and_the_app_limit_before_apple(self):
        install = self.intents["CartoucheInstallAppIntent"]
        # perform() refuses first, then installs: the refusal's call comes
        # before the install's in its body.
        perform = install[install.index("func perform()"):]
        refusal = perform.find("try await self.refuseWhatIsNotCartouchesToInstall(")
        self.assertGreater(refusal, 0, "perform() never refuses")
        self.assertLess(refusal, perform.index("AppManager.shared.install("), "the refusal comes after the install")
        for reason in ("anotherStoresApp", "appLimit"):
            with self.subTest(reason=reason):
                self.assertIn(f"CartoucheAppsError.{reason}(", install, f"{reason} is never thrown")

    def test_the_removal_clears_an_app_that_is_gone(self):
        remove = self.intents["CartoucheRemoveAppIntent"]
        self.assertIn("deleteApp(", remove)
        caught = remove[remove.index("catch"):]
        self.assertIn("removeApp(", caught)

    def test_the_built_in_sidestore_runs_one_action_at_a_time(self):
        # The bridge takes one action (RefreshHandler): an install, a renewal
        # or a removal waits for Renew now and the update, and they for it;
        # a refused install leaves no IPA copy behind.
        model = read(LAUNCHER)
        renewal = read(ROOT / "launcher" / "Sources" / "CartoucheRenewal.swift")
        system = read(ROOT / "launcher" / "Sources" / "CartoucheSystemView.swift")
        self.assertIn("static private(set) var isRenewing", renewal)
        self.assertIn("CartoucheRenewal.isRenewing", model)
        self.assertIn("CartoucheUpdates.shared.phase", model)
        self.assertIn("removeItem(at: copy)", model)
        renew_button = system.index("Button(CartoucheText.renewNow")
        self.assertIn("apps.work != nil", system[renew_button:renew_button + 600])
        update_button = system.index("Button(CartoucheText.updateTo")
        self.assertIn("apps.work != nil", system[update_button:update_button + 400])

    def test_a_renewals_failed_apps_are_named_from_the_list_and_a_nights_taken_first(self):
        # Renew now may run before the section ever loaded its apps, and it
        # clears the keychain item a night's renewal left: the failures are
        # named from the list in the app group, and the night's outcome is
        # taken before Renew now begins.
        model = read(LAUNCHER)
        renewal = read(ROOT / "launcher" / "Sources" / "CartoucheRenewal.swift")
        note = model[model.index("func noteRenewal("):]
        note = note[:note.index("\n    }\n")]
        self.assertIn("Self.listed", note)
        self.assertNotIn("for app in apps", note)
        renew = renewal[renewal.index("static func renew(progress: Progress"):]
        taken = renew.index("CartoucheIPhoneApps.shared.takeNightlyOutcome()")
        self.assertLess(taken, renew.index("CartoucheStoreKeychain.remove("))

    def test_the_apps_that_failed_stay_out_of_the_measurements(self):
        # The outcome's facts go to the telemetry with a renewal's event
        # (CartoucheFailure.sideStoreSuccess); bundle identifiers never do.
        failure = read(ROOT / "launcher" / "Sources" / "CartoucheFailure.swift")
        self.assertIn("var failedApps: [String]", failure)
        self.assertIn("CartoucheIPhoneAppList.failedIdentifiers(written.texts[.failed])", failure)
        self.assertNotIn('facts["failed"]', failure)

    def test_the_bridge_runs_the_four_intents(self):
        bridge = read(BRIDGE)
        self.assertIn("@objc(CartoucheApps)\npublic final class CartoucheApps", bridge)
        for selector in SELECTORS:
            self.assertIn(f"@objc({selector})\n    public static func", bridge)
        calls = re.findall(r'performIntentRefresh\(\s*identifier:\s*"([^"]+)",\s*mangledTypeName:\s*"([^"]+)"', bridge)
        self.assertEqual([identifier for identifier, _ in calls], list(INTENTS))
        for identifier, mangled in calls:
            self.assertEqual(mangled, f"{len(MODULE)}{MODULE}{len(identifier)}{identifier}V")

    def test_the_launcher_finds_the_bridge_by_its_names(self):
        launcher = read(LAUNCHER)
        self.assertIn('NSClassFromString("CartoucheApps")', launcher)
        for selector in SELECTORS:
            self.assertIn(f'NSSelectorFromString("{selector}")', launcher)


if __name__ == "__main__":
    unittest.main()
