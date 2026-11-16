# The README's pictures

The pictures of the repository's [README](../../README.md), made from the app's own screenshots:

| File | What it shows | Made from |
| --- | --- | --- |
| `devices.png` | Cartouche Builder's library beside the sheet of a game, with Play on this Mac and Console and Builder at the top of the window, on a MacBook Air; in front of it, the home beside the sheet of the game in focus, paused behind the console, landscape on an iPad Pro 13-inch, and the home, landscape on an iPhone 17 Pro | The Builder's gallery, `game-en-light` (since #201), and the app's, `ipad-home-paused-landscape` and `iphone-home-landscape`, in English; the iPad's status bar without the name of the gallery's app |
| `screens.png` | All games, a game paused behind the console, a game's settings | The gallery's `iphone-library`, `iphone-home-paused` and `iphone-game-settings`, in English |
| `builder.png` | Cartouche Builder's library, with a game's sheet: Play on this Mac, and what the game is built for; Console and Builder at the top of the window | The Builder's gallery, `game-en-light` (since #201) |
| `icon.png` | Cartouche's icon, with the corners iOS gives it | [`app/icon`](../../app/icon/) |
| `download-*.png` | The download buttons | Drawn for the README |
| `dev-apps.png` | The home with two apps that are not games after the game (branch `dev`) | The gallery's `iphone-apps`, in English, as it is |
| `dev-app-sheet.png` | An app's sheet (branch `dev`) | The gallery's `iphone-app-sheet`, in English, as it is |
| `dev-app-settings.png` | An app's settings page, Needs JIT on (branch `dev`) | The gallery's `iphone-app-settings`, in English, as it is |
| `dev-apps-on-iphone.png` | Apps on this iPhone, two apps with their App ID (branch `dev`) | The gallery's `iphone-apps-on-iphone`, in English, as it is |
| `dev-app-ids.png` | The App IDs Apple keeps for the Apple ID (branch `dev`) | The gallery's `iphone-app-ids`, in English, as it is |

The screenshots are the ones CI takes of every screen: the Launcher screens workflow, with `"language": "en"` in [`launcher/Gallery/scenarios.json`](../../launcher/Gallery/scenarios.json), for the app, and the Builder workflow for Cartouche Builder. Each iPhone or iPad is drawn around its screenshot on Cartouche's colours, and the Mac around its window, on a desktop with its menu bar; the iPad and the iPhone of `devices.png` at the same size for their points.

The `dev-*.png` pictures of the fork's `dev` branch are the gallery's screenshots as they come out, not framed: `launcher/Gallery/capture.sh` on the iPad Pro 13-inch simulator, with `"language": "en"` and the scenario list cut to those five.

The games show their official covers, as in the app, which loads them from IGDB ([decision 83](../decisions.md)). Never an image from inside a game: no capture of a game running, and no game's screenshot. The download buttons link to the [download page](https://cartouche-app.github.io/Cartouche/download/), which gives the newest file, and say no version.
