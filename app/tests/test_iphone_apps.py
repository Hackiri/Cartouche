"""Checks that the apps Cartouche installs on this iPhone through the built-in
SideStore (app/patches/sidestore/0022, decision 88) line up across the three
sides that make them work:

- the patch adds the three actions, install, refresh and remove, headless:
  no page of SideStore's, no prompt, not listed by Shortcuts;
- they read the request and keep the list Cartouche writes in the app
  group, under the names the launcher writes them by;
- the install refuses another store's app and the three-app limit before
  anything goes to Apple, and the removal clears an app that is already
  gone from the home screen;
- CartoucheApps (launcher/SideStoreSupport) runs the three actions by
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
INTENTS = ("CartoucheInstallAppIntent", "CartoucheRefreshAppsIntent", "CartoucheRemoveAppIntent")
SELECTORS = ("installAppWithProgress:completion:", "refreshAppsWithProgress:completion:",
             "removeAppWithProgress:completion:")


def apps_patch() -> Path:
    patches = sorted(PATCHES.glob("*-install-renew-and-remove-apps-for-cartouche.patch"))
    if len(patches) != 1:
        raise AssertionError(f"expected one apps patch in {PATCHES.relative_to(ROOT)}, found {len(patches)}")
    return patches[0]


def added_files() -> dict:
    """The lines patch 0022 adds, by the file they go to."""
    files, current = {}, None
    for line in apps_patch().read_text(encoding="utf-8").splitlines():
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

    def test_the_patch_adds_the_three_intents(self):
        for name, text in self.intents.items():
            with self.subTest(intent=name):
                self.assertIn(f"struct {name}: AppIntent", text)
                self.assertIn("static var openAppWhenRun = false", text)
                self.assertIn("static var isDiscoverable: Bool { false }", text)
                # Every call into SideStore is headless.
                calls = re.findall(r"AppManager\.shared\.\w+\((?:[^()]|\([^()]*\))*\)", text, re.S)
                self.assertTrue(calls, "no AppManager call")
                for call in calls:
                    if "presentingViewController" in call:
                        self.assertIn("presentingViewController: nil", call, call)
                self.assertEqual(set(re.findall(r"presentingViewController: (\w+)", text)), {"nil"})

    def test_the_intents_read_the_request_and_the_list_cartouche_writes(self):
        launcher = read(LAUNCHER)
        for name in ('"CartoucheAppsRequest"', '"CartoucheInstalledApps"', '"ipa"', '"apps"', '"app"'):
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

    def test_the_bridge_runs_the_three_intents(self):
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
