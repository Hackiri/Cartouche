# Local wireless: playing a game together, iPhone to iPhone

Date: 2026-11-13. Status: designed, not built; to be decision 138 in
[docs/decisions.md](../../decisions.md) when built. The plan is beside it in
`../plans/`.

## Intent

A Switch plays Mario Kart 8 Deluxe with the consoles around it over *local
wireless*: Nintendo's `ldn` service makes one console an access point, the
others its stations, and the game sends its race packets over that little
network with ordinary sockets. On an iPhone, nxnative takes the offline
branch of every network call today: Wireless Play's menu says no console was
found.

The player wants two or more iPhones (or an iPad, or a Mac running the same
game) in the same room to find each other and race, with nothing but the
Wi-Fi they already share, and nothing of Nintendo's online. Every peer runs
its own copy of the game, built from its own files (decision 1).

## What exists

- **nxnative is where the Switch's services are answered.** A game's own SDK
  code runs natively; the host takes over `nn::` functions by name
  (`HLE_FORCE` in `dm/host/hle_*.c`). `hle_net.c` answers `nn::socket` and
  `nn::nifm` as "network down" and no `nn::ldn` call is hooked: a game that
  calls one aborts or sees no console.
- **nxnative pull request [#846](https://github.com/seedds/nxnative/pull/846)**,
  open since 2026-11-01 (RobiiAragon, from NX Port Studio), adds exactly this:
  `hle_ldn.c` answers `nn::ldn` with ldn_mitm's wire format (the one modded
  Switches and Ryujinx's LAN mode speak), `hle_net_backend.c` gives
  `nn::socket` real IPv4 sockets on the device's Wi-Fi, and discovery is a
  bounded unicast sweep of the subnet (`net_discovery.h`), never a broadcast
  or a multicast, which iOS refuses to an app without Apple's multicast
  entitlement. It is opt-in by environment: `DM_NETWORK=ldn` (or `lan`,
  `auto`; `offline` is the default), `DM_NET_DISCOVERY_PEER=<ip>` names one
  peer instead of sweeping, `DM_NET_TRACE=1` logs the traffic. Its author
  raced Mario Kart 8 Deluxe 3.0.5 between Mac and iOS builds and a modded
  Switch. Issue #1175 (Ldn_mitm multiplayer support) was closed as completed
  on 2026-11-09, but #846 is not merged and has no maintainer review yet;
  issue #951 holds the author's wider online plans, which this design leaves
  out.
- **Cartouche already asks iOS for the local network**: `app/scripts/package.sh`
  writes `NSLocalNetworkUsageDescription` and `NSBonjourServices`
  (`_cartouche._tcp`) into Cartouche's `Info.plist` for the shared folders and
  Cartouche Builder. The game's process is LiveContainer's `LiveProcess`
  extension, whose `Info.plist` package.sh already edits for Game Mode.
- **Cartouche Builder takes nxnative from any Git URL and branch**
  (`engine_url`, `engine_branch` in its `config.json`,
  `builder/cartouche_builder/config.py`), and a game built from a commit
  `main` does not have is shown as a fork's, not as stale (decision 66).
- **A game's settings page is nxnative's list drawn by Cartouche**: the
  built app's `dm/launcher.json` (`docs/frontends.md`) names each setting's
  environment switch, kind, section and default; a section Cartouche does
  not know is drawn under its name like the others.

## Goals

- **Two iPhones on one Wi-Fi race each other** in Mario Kart 8 Deluxe's
  Wireless Play: one creates the room, the other finds it in the game's own
  menu and joins; a Grand Prix completes. Up to the eight players the game
  allows, any mix of iPhones, iPads and Macs running nxnative builds.
- **No router needed**: one iPhone's Personal Hotspot is a Wi-Fi the others
  join; the sweep covers its /28.
- **One setting per game, off by default**: **Local wireless** on the game's
  settings page, where nxnative's other settings are. Nothing of it runs
  while it is off: no socket opens, no sweep, no permission prompt.
- **iOS's one question**, the local network prompt, says why in Cartouche's
  words, for the app and for the game's process.
- **Said plainly where it fails**: the game's own menu shows "no console
  found" when the Wi-Fi isolates clients or the setting is off on the other
  device; Cartouche's documents say what to check, and a trace switch gives
  the report to copy.
- **Nothing leaves the room**: no server of Cartouche's or anyone's, no
  internet matchmaking, no account; the measurements gain nothing that names
  a network or a peer.

## Non-goals

- Nintendo's online play, NEX, friends, Nextendo or any other replacement
  service (#951): out of scope here, and out of Cartouche's (decision 1 and
  the roadmap's *Not planned*).
- Peer-to-peer Wi-Fi without any network, through AWDL or Bluetooth: left to
  *Later* (see below), because it needs Bonjour discovery in the host and
  the Network framework's peer-to-peer connections, which the ldn_mitm wire
  format over plain sockets does not give.
- Games that speak LAN play rather than local wireless (`DM_NETWORK=lan`,
  Pia's LAN discovery on port 30000): the bridge supports them and the same
  setting may offer *LAN* later; nothing in this design tests one.
- Reimplementing LDN in Cartouche: the launcher never touches a game's
  packets.

## Anti-goals

- A multicast entitlement, a paid developer account or a Cartouche Installer
  change: a free Apple ID must be enough, as for everything else.
- A fork of nxnative that drifts: the fork carries #846 rebased on upstream
  main and nothing else, and goes away when upstream merges.
- Any change to how games are packaged, signed or installed.

## Constraints

- **The host decides, Cartouche carries.** All emulation of `ldn` and the
  sockets lives in nxnative (#846). Cartouche's part is to get that code into
  the player's builds, to ask iOS for the network, to show the setting and
  to explain it.
- **iOS 14 and later forbid IP broadcast and multicast** to apps without
  `com.apple.developer.networking.multicast`, which Apple grants per app to
  paid teams. #846's unicast sweep (a /24 is 254 hosts, 8 batches of 32, 8 ms
  apart: about 70 ms) is the discovery; `dm_net_set_multicast_allowed` stays
  off on iOS.
- **The local network prompt** (`NSLocalNetworkUsageDescription`) is asked
  of the process that first reaches the network: the game's, in
  `LiveProcess.appex`, or Cartouche's when the game starts in its place. Both
  `Info.plist` files get the key, with one text that names the shared
  folders, the Builder and local wireless play. Whether iOS reads the
  extension's key or the app's is measured on the iPhone (Review Focus 1).
- **Wi-Fi client isolation** (hotel, campus, guest networks) blocks the sweep
  and every packet; a Personal Hotspot does not. The documents say so.
- **Same game, same version, on every device.** LDN carries the game's
  version in its network info and refuses a mismatch (`LDN_VERSION_LOW/HIGH`).
  Mario Kart 8 Deluxe 4.0.1 on both, each from its owner's files.
- **ldn_mitm authenticates nothing** (its control TCP and the passphrase are
  not checked, as #846's header says): the setting is off by default, and
  the documents call it a local-network transport, not Nintendo's security.
- **The Builder's weekly rebuild policy** rebuilds a game when nxnative's
  shared code changes; a fork branch rebased on upstream main every week
  keeps the player current and keeps the fork's only change #846.
- **Decision 66**: a game built from the fork shows as a fork's build; its
  sheet must not nag to rebuild from `main` while the fork is the point.

## Approaches

1. **Carry nxnative #846 through a fork branch, and the setting through
   nxnative's own list** (chosen). Cartouche Builder is pointed at
   `https://github.com/Hackiri/nxnative.git`, branch `ldn` = upstream `main`
   with #846 rebased, plus a `settings.tsv` row that puts `DM_NETWORK` on the
   settings list under a **Local wireless** section. Cartouche needs no new
   screen: the toggle appears on every game's settings page from the built
   app's `launcher.json`. Cartouche changes: the two `Info.plist` texts, the
   documents, the Builder's defaults and the guide. When upstream merges
   #846, the Builder goes back to `main`.
2. **Cartouche writes `DM_NETWORK=ldn` into the game's `Documents/env.txt`**
   from a switch of its own on the game's sheet, as it writes
   `DM_LAUNCHER=0` today. Works with any build that has the bridge, no
   `settings.tsv` change, but it hides the setting from nxnative's own screen
   on the Mac, duplicates a settings row Cartouche otherwise never owns, and
   an `env.txt` line wins over the player's later choice on the settings
   page ("Lines in the app's `Documents/env.txt` win over that screen").
   Rejected; kept as the fallback if upstream wants no settings row.
3. **Implement LDN in Cartouche, outside the game**: a LiveContainer
   tweak-style dylib in the game's process hooking the same symbols. Twice
   the work of #846 with none of its tests, and against nxnative's grain,
   where every service answer lives in the host. Rejected.
4. **Wait for upstream.** #846 has waited since 2026-11-01 without review; a
   player with two iPhones should not.

## Design, as decided

### nxnative, by a fork branch (`Hackiri/nxnative`, branch `ldn`)

- `ldn` = upstream `main` + #846's commits rebased, resolved where upstream
  moved, with #846's tests green (`dm/host/tests/t_ldn.c`, `t_net.c`,
  `t_net_discovery.c`, `t_discovery_protocol.c`, `t_ldn_events.c`). Nothing
  of #846's `friends_history` or `account_local` is needed for LDN; they
  stay as #846 has them to keep the rebase a rebase.
- One commit of our own: `dm/games/settings.tsv` gains a row for
  `DM_NETWORK`: kind `choice`, section `Local wireless`, label
  `Local wireless`, options `offline` = *Off*, `ldn` = *On this Wi-Fi*,
  default `offline`, note: "Finds the other players' devices on this Wi-Fi,
  as a Switch's local wireless does. Every device runs its own copy of the
  game, same version. Off, nothing reaches the network." A sub-row
  `DM_NET_TRACE`, toggle, `needs DM_NETWORK=ldn`, label *Network trace*,
  for the report. `dm/games/settings.py` regenerates `launcher.json` from
  it, as for every setting. Whether a per-game profile can hide the row for
  games with no local wireless is left to the builder (Review Focus 4).
- The same row is offered upstream as a comment on #846, with the iOS
  findings (the unicast sweep works without the entitlement; the prompt;
  the hotspot's /28), so the fork can go.

### Cartouche Builder (`builder/`)

- Defaults unchanged (`ENGINE_URL`, `ENGINE_BRANCH` = upstream `main`); the
  README's *Settings* gains a paragraph: to play local wireless until
  upstream merges #846, set `engine_url` to the fork and `engine_branch` to
  `ldn`, and every game is rebuilt from it by the weekly policy.
- Decision 66's sheet text, for a game whose commit `main` does not have,
  stays; a game built from the configured `engine_url`/`engine_branch` is
  not a fork's to the Builder, since the Builder's own engine checkout is
  that branch.

### The app (`app/scripts/package.sh`, the game's process)

- `NSLocalNetworkUsageDescription`, English and French, now says:
  "Cartouche connects to Cartouche Builder on your Mac and to the shared
  folders of your Mac, PC or NAS on this network to keep your games and
  saves there, and lets a game with Local wireless on find the other
  players' devices on it." The same key, same text, goes into
  `PlugIns/LiveProcess.appex/Info.plist` next to the Game Mode keys.
- No new Bonjour type: the sweep and the game's packets are plain IPv4.
- No entitlement change.

### The launcher (`launcher/Sources`)

- No new screen. **Game settings** draws the *Local wireless* section from
  `launcher.json` as any other (`CartoucheGameSettings.swift`); the gallery's
  sample list gains the two rows so the UI test and the screenshot show
  them (`iphone-game-settings-wireless`).
- The game's sheet shows nothing new. A later step may show *Local wireless
  on* under the game's name, from the saved choice, so a player sees why a
  game asked for the local network.

### Documents

- `docs/decisions.md`: decision 138, with 1 and 66 cross-referenced.
- `docs/roadmap.md`: under *Next*, "Local wireless between iPhones (decision
  138), raced on two devices"; under *Later*, "Local wireless with no Wi-Fi
  around, over peer-to-peer Wi-Fi (AWDL): Bonjour discovery in the host and
  the Network framework's peer-to-peer connections".
- `docs/getting-started.md` and `.fr.md`: a short *Play together* section:
  same Wi-Fi or one iPhone's Personal Hotspot, the setting on each device,
  the game's own Wireless Play menu, what a guest network does.
- `docs/privacy.md`: the local network is used for the shared folders, the
  Builder and local wireless play; nothing of it is measured or sent.
- `README.md` (this fork's section) and `launcher/README.md` (Game settings:
  a section the list adds is drawn like the others, local wireless being
  one); `builder/README.md` as above.

## Left to the builder

- The exact `settings.tsv` columns and how `settings.py` carries `needs`;
  whether `choice` or `toggle` fits the *Off / On this Wi-Fi* row best.
- The rebase of #846 on the upstream `main` of the day: the plan pins the
  commits it was rebased on.
- Whether iOS's prompt comes from `LiveProcess.appex`'s key or the app's:
  both carry it; the answer goes in the decision's row.
- MK8D's Wireless Play on nxnative at 60 fps with the bridge on: the first
  real race decides whether the host needs a frame-rate note.

## Later

- **Peer-to-peer without a network**: `NWBrowser`/`NWListener` on
  `_nxnative-ldn._udp` with `includePeerToPeer`, feeding the bridge's
  transport with the peers' addresses instead of the sweep; needs a Bonjour
  type in both `Info.plist` files and a transport hook in `hle_ldn.c`.
- **LAN play** (`DM_NETWORK=lan`) for the games that have it, as a third
  option of the same setting.
- **Interoperability notes** with Ryujinx's LAN mode and ldn_mitm Switches on
  the same Wi-Fi, once tried.
