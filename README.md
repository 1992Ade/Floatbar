# TrollBox

> *A single-icon re-bundle of iOS 14-16 TrollStore utilities I use daily.*

**TrollBox** is a re-bundle of various existing TrollStore utilities I find
useful and functional on iOS 14-16 (device of reference: iPhone SE 1st-gen
on iOS 15.8.8). Other similar tools exist, but these are the ones I actually
use; rather than switching between ten apps I put mine under one icon.
Install once, pick what you need from the home grid.

**No jailbreak. No MobileSubstrate / ElleKit.** TrollStore's
`platform-application` entitlement is enough. TrollBox self-elevates to
`euid=0` in `main()` so every section can write to the root-owned paths it
needs (CC bundles, LaunchDaemons, SpringBoard managed prefs, system log
rotations…) without the `rootSpawn` dance.

**Compatibility**: iOS 14.0 - 16.6.1, any device TrollStore runs on - the
A9 iPhone 6s / SE 1st-gen, iPad Pro 2018 (A12X), everything in between. The
Ad Blocking profile the app generates also installs on **non-TrollStore**
iPhones once they're supervised via Apple Configurator 2 (see the "For
non-TrollStore users" section below).

**Latest release**: [github.com/1992Ade/TrollBox/releases/latest](https://github.com/1992Ade/TrollBox/releases/latest)

## Home grid order

1. **LocSim**
2. **Ad Blocking**
3. **Reclaim Space**
4. **AppRepack**
5. **SpringBoard Tweaks** — Badge Color + Clear All + Don't Lock
6. **ResSetter** — restored in 2.0.2 with write path ported from haoict's IPA
7. **ClearShot**
8. **Supervise**
9. **Tweaks**
10. **Saved WiFi**
11. **About Device** (includes Diagnostics)
12. **About**

> **ResSetter 2.0.2 rewrite.** The 2.0.0 brick cause was the write path:
> `writeToURL:` on the root-owned system plist silently failed at euid=501,
> leaving the file untouched after Apply and uncleanable after Reset. In
> 2.0.2 the write path is ported from haoict's ResolutionSetterSwift 1.1
> IPA (reverse-engineered from the shipped binary): stage the XML plist in
> `/private/var/tmp/com.trollbox.iokit/`, then `rootSpawn /bin/cp -f` to
> the system destination. Reset follows the same pattern — three
> `rootSpawn /bin/rm -f` calls, one per poison file. This is the mechanism
> haoict's own app has used in production since the TrollStore port
> landed.
>
> **If you installed 2.0.0 and your display is unusable**, see
> `docs/RECOVERY.md` — summary: Voice Control via Siri (`Hey Siri, turn on
> Voice Control` → `Show grid` → tap the passcode digits by name →
> delete `/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist`,
> `/var/mobile/Library/Preferences/TrollBoxGfxBackup.plist`,
> `/Library/LaunchDaemons/com.trollbox.ressetter.plist`, reboot). ResSetter
> 2.0.2's own Reset button handles this automatically now — the 2.0.0 one
> couldn't.

## Sections

### LocSim — simulated CLLocation
Feeds a fake GPS fix to every app via the private `CLSimulationManager`.
Port of Andromeda's MapKit UI: long-press on the map to drop a pin, use the
search bar for named places, save favourites you come back to, tap the
re-center button to zoom (~500 m) on your real current location when you
need to pick a spot near you.

### Ad Blocking — MYbloXX-style blocker, PACs embedded locally
Port of [MYbloXX for iOS](https://github.com/pegakmupyem/myxxdev) with the
blocklists shipped **inside the app**: no PAC is fetched over HTTP at
install time, no third-party server sees your traffic. Four PAC variants
(Standard / noFB / noXXX / noFBnoXXX), each ~83,521 domains merged from
MYbloXX + StevenBlack at build time. Three user toggles:

- **Allow Facebook/Instagram login** — unblocks the FB/IG SDK login
  endpoints only, keeps all tracker domains blocked. Switch this on if FB
  or Instagram log-in screens fail to load.
- **Block adult content** — adds ~45 wildcard filters for adult keywords on
  top of the baseline.
- **Block iOS updates** — installs a fake tvOS Beta Software Profile that
  silences iOS Software Update. Reversible. **Enable this if you also use
  ClearShot's native-gesture hook**, so you don't accidentally update iOS
  with an injected SpringBoard dylib.

Also an in-app "Refresh blocklist from StevenBlack" button so you can pull
a fresher list between releases. `isProfileInstalled` wrapped in defensive
`@try/@catch` + `respondsToSelector:` so entitlement-stripped builds or
MCProfileConnection API drift can no longer crash the section on open.

### Reclaim Space — free real disk space
Targeted replacement for the generic iOS "cleanup" tools that free
basically nothing. Scans the paths iOS actually leaves lying around:

- Analytics panics (`CrashReporter/Analytics/*.synced`)
- Crash reports (`CrashReporter/*.synced`)
- AppleSupport / Feedback Assistant logs
- Rotated system logs (`/var/log/*.log.*` — root-owned, works at `euid=0`)
- Orphaned app containers (bundleId no longer installed)
- **App caches** — `Library/Caches/*` per installed app
- **App tmp** — `tmp/*` per installed app
- **System caches** — whitelisted subset (dyld, LinkPresentation, newsd, …)
- **Daemon caches** — WebKit, nsurlsessiond, Suggestions, CloudKit

Shows real sizes before + after, so you know how much was actually freed.
Delete failures are captured and reported in About Device → Diagnostics.

### AppRepack — install older **and newer** app versions
Port of [Muffinstore](https://github.com/mineek/muffinstore) plus a
MinimumOSVersion patcher. Pick an installed app or paste an AppStore URL;
TrollBox fetches the version history from `apis.bilin.eu.org` and presents
a custom color-coded picker (not a cramped ActionSheet):

- 🟢 Highest version compatible with your iOS — Apple picks this when you
  tap "⭐ Latest compatible"
- 🔴 Newer versions above your iOS — require MinimumOSVersion patching
- 🔵 Older versions — install directly via `SKUIItemStateCenter`

Full history visible, newest-first, no 10-version cap. For newer versions
there's a gap-aware warning dialog + an option to patch a manually-
downloaded `.ipa` via the Files app.

**Realistic success rate after MinimumOSVersion patch, apps 1 iOS major above:**

| App type | Success |
|---|---|
| WebView wrappers (Instagram, X, banking, delivery) | ~95 % |
| Classic UIKit apps | ~60 % |
| Recent SwiftUI apps | ~30 % |
| Games / AR / Core ML | ~10 % |
| Apple system apps | ~0 % |

2 majors above: divide those numbers by three. 3+ majors: forget it.

The patcher rewrites `Payload/App.app/Info.plist`'s `MinimumOSVersion` and
the Mach-O `LC_BUILD_VERSION` / `LC_VERSION_MIN_IPHONEOS` `minos` field.
It does NOT decrypt FairPlay — iOS still decrypts the `__TEXT.__text`
section at launch using your Apple ID's local key.

Your Apple ID session already active on this device handles authentication
— TrollBox never sees your password.

### ResSetter — display resolution, slider-driven
Writes `canvas_width` / `canvas_height` to
`com.apple.iokit.IOMobileGraphicsFamily.plist` so iOS reports your chosen
logical resolution.

**UI: a slider from ×1.00 to ×1.50**, 0.01-step, persisted in
`NSUserDefaults`. `Target = native × factor`, rounded. Apply + respring
picks it up. Reboot reverts (unless Re-apply at boot is on).

**Critical fix from a 2026-11-28 field report**: previous builds wrote the
plist in portrait form (`canvas_width = short side`), which the iOS
compositor interprets in landscape convention — causing tiling and visual
artifacts at certain scales (notably ×1.2 on A9). Current build always
writes landscape form (`canvas_width = long side`) to match Apple's native
convention and haoict's ResolutionSetterSwift.

Two Persistence toggles:

- **Re-apply at every boot** — installs a LaunchDaemon that restores your
  last-applied size before backboardd each boot. Written directly via
  `NSFileManager` + `chown()`/`chmod()` syscalls (no `rootSpawn` needed
  since the app runs at `euid=0`); keeps `rootSpawn` as a defensive
  fallback with full stderr capture. Safe-boot disables it so you can
  recover from a bad choice.
- **Don't lock device after respring** — writes `SBDontLockAfterCrash=YES`
  to `/var/Managed Preferences/mobile/com.apple.springboard.plist`.
  Mirrored in SpringBoard Tweaks, Badge Color and ClearShot — same key,
  all four stay in sync. (Mechanism ported out of Jaility.)

**Recovery**: a dedicated **Reset to native** button nukes every trace
ResSetter left behind — LaunchDaemon file, backup plist, `canvas_*`
keys in the gfx plist, persisted factor in NSUserDefaults — then prompts
a respring. Use this if any prior apply left the device with artifacts.

### SpringBoard Tweaks — Badge Color + Clear All + Don't Lock
Dedicated home for SpringBoard-side modifications:

- **Badge Color** (push row → the full Badge Color screen) — port of
  Cowabunga's BadgeChanger. Draws a filled circle of your chosen `UIColor`
  at a chosen radius, writes it to the SpringBoard badge bitmap cache.
  Persist-on-apply: reopening restores your last confirmed color/radius.
  The live preview now shows an actual home-screen icon with the badge
  pip on top, instead of a dark grey square.
- **Clear All in app switcher** (toggle) — injects `libClearAllHook.dylib`
  into SpringBoard via the Tweaks engine (TFInjector). After the respring,
  the native app switcher gets a **Clear All** button in the top right
  that kills every running process EXCEPT SpringBoard, backboardd,
  mediaserverd, cfprefsd, launchd, lockdownd, trustd, trollstored and
  TrollBox itself (so you don't force a respring or break audio).
- **Don't lock after respring** (toggle) — mirror of the same
  `SBDontLockAfterCrash` key. Change it here or in ResSetter / Badge Color
  / ClearShot — the four stay in sync.
- **Uninject all SB hooks + respring** (red destructive) — single-tap
  cleanup before an iOS update so SpringBoard launches with no injected
  dylibs on the new system.

### ClearShot — Control Center screenshot that bypasses FLAG_SECURE
Installs `ClearShotModule.bundle` in `/Library/ControlCenter/Bundles/`.
From any app, swipe into Control Center → tap the tile → the screenshot
lands in Photos even when the foreground app has FLAG_SECURE set (banking,
auth, secure messaging). Uses `CARenderServerRenderDisplay` from inside
SpringBoard.

**Three capture paths, pick what fits:**

| Path | Latency | Setup | Device | Status |
|---|---|---|---|---|
| CC module (Capture + Record) | ~250 ms (CC auto-dismiss) | tile added to Control Center | all | stable (default) |
| Native gesture hook (Power + Home → bypass) | 0 ms, native | one tap in Tweaks to inject `libClearShotHook.dylib` into SpringBoard | all | stable, experimental |

Native gesture hook uses our own Tweaks engine (TFInjector) — no external
app required. The hook does `method_exchangeImplementations` on
`SBScreenshotManager _writeScreenshotToCameraRoll:` so every native
screenshot gesture bypasses FLAG_SECURE system-wide. **Install Ad Blocking's
"Block iOS updates" first** so you don't accidentally OTA-update with an
injected dylib still in place; the section cross-links to it.

The Record CC module records video (CARenderServer + `IOSurface` +
`AVAssetWriter` zero-copy at 30 FPS by default). While recording, a thin
red overlay over the status-bar clock pulses sinusoidally; tap it to stop.
A sub-screen "Record settings" lets you pick FPS (15/24/30/60), resolution
(native/720p/480p), audio (system + microphone toggles) and format
(H.264/HEVC).

Full diagnostics for every section live in About Device → Diagnostics
(single place, not a per-section button).

### Supervise — IsSupervised spoof
Toggles the `IsSupervised` flag (and an optional `OrganizationName`) in
`CloudConfigurationDetails.plist`. Unlocks a handful of supervised-only
iOS settings; same mechanism Ad Blocking uses under the hood.

### Tweaks — dylib / bundle injection (TrollFools port)
In-app injection engine ported from
[TrollFools](https://github.com/Lessica/TrollFools) by Lessica. Pick a
target app from the installed list, pick a `.dylib` / `.deb` / `.bundle`
from Files, TrollBox patches the Mach-O load commands and re-signs.
Separate screen per app shows what's currently injected, with an **Eject**
swipe to remove. Preamble card points at well-maintained TrollStore-
compatible tweak sources (YTLite, BHInstagram, BHTwitter, etc.).

The engine lives behind `TFInjector` / `TFMachO` / `TFCodesign` and is
reused by ClearShot's native-gesture hook (same injection path, different
caller).

### Saved WiFi — view, reveal, forget, export
Lists every network iOS remembers (reads
`/var/preferences/com.apple.wifi-known-networks.plist` on iOS 15+, falls
back to the legacy `/var/preferences/SystemConfiguration/com.apple.wifi.plist`).
Tap an SSID to reveal the stored password (SecItemCopyMatching against the
`AirPort` keychain service, via our added `keychain-access-groups`), swipe
left to forget. Export the whole list as CSV via the share sheet. Shows
your currently-connected SSID at the top, sorts saved networks by last
auto-join date. **Warning**: if iCloud Keychain is on, forgotten networks
may resync from your other Apple devices within hours.

### About Device — battery, device, CPU, RAM, storage, network, Diagnostics
Reads the private `IOPowerSources` keys that normal apps can't surface:

- Design capacity, Current max (AppleRawMaxCapacity), Nominal charge
- Battery health (%)
- Cycle count
- Voltage (V)
- **Current** (Amperage, mA) — negative when discharging, positive when charging
- **Instant current** (InstantAmperage, mA)
- **Power** (W) — computed from V × A
- Temperature (°C)
- Time remaining
- **Adapter** (name, watts, wireless flag) — appears only when plugged in

Auto-refreshes the Battery section at 1.5 s cadence (NiceBattery-style);
timer invalidates when you leave the screen so there's zero cost when
hidden. Plus the usual device / CPU / RAM / storage / network panes.

**Diagnostics** row at the bottom opens a scrollable report aggregating:

- Process identity (pid, uid, euid, gid, egid) — confirms the `setuid(0)`
  elevation worked (`euid=0` ✅ or fallback warning)
- iOS version, device machine, bundle path + version
- Writability (`access(path, W_OK)`) of every root-owned path TrollBox
  writes to (12 paths)
- Each section's own diagnostic info (via a `TBDiagnosticProvider`
  protocol) — self-reported state, last error, cached counters

Copy or share the whole report; attach it to a bug report.

### About — version, credits, license
Credits every upstream project the sections are ported from, plus the
icon author (c22dev) and the development assistant (Claude by Anthropic).

## Install on device

### With TrollStore (primary path)

1. Download **TrollBox.tipa** from the
   [latest release](https://github.com/1992Ade/TrollBox/releases/latest/download/TrollBox.tipa).
   In TrollStore, open **Install from URL** and paste:
   ```
   https://github.com/1992Ade/TrollBox/releases/latest/download/TrollBox.tipa
   ```
2. Open **TrollBox** from the Home Screen. The app self-elevates to root
   in `main()` so every section just works — if you see `euid=501` in
   About Device → Diagnostics, something went wrong at `setuid(0)` and the
   diagnostics report will say which path is unwritable.
3. For ClearShot: tap the tile → **1 · Install Control Center module** →
   **2 · Respring now** → **3 · Open Control Center settings**, scroll to
   *More Controls* and tap **+** next to **ClearShot** and **Record**.
4. For Ad Blocking: tap the tile → toggle filters → **Generate & install
   profile**. Enable supervision in the same screen if prompted.
5. Other sections work out of the box — no install step.

### For non-TrollStore users

TrollBox itself needs TrollStore (it uses the `platform-application`
entitlement that only TrollStore grants). But **the Ad Blocking profile it
generates installs on any supervised iPhone**, no TrollStore required.
Two paths:

**Option (a) — Download pre-generated mobileconfigs (easier)**

Each GitHub Release attaches 8 ready-made `.mobileconfig` files, one per
toggle combo:
```
TrollBoxAdBlock-Standard.mobileconfig
TrollBoxAdBlock-noFB.mobileconfig
TrollBoxAdBlock-noXXX.mobileconfig
TrollBoxAdBlock-noFBnoXXX.mobileconfig
TrollBoxAdBlock-Standard-noOTA.mobileconfig
TrollBoxAdBlock-noFB-noOTA.mobileconfig
TrollBoxAdBlock-noXXX-noOTA.mobileconfig
TrollBoxAdBlock-noFBnoXXX-noOTA.mobileconfig
```

Pick the one you want, open it on your iPhone in Safari, install via
Settings → Profile Downloaded. For the install to be accepted the iPhone
must already be supervised, which you do from a Mac:

1. Back up your iPhone — supervising wipes it.
2. Install [Apple Configurator 2](https://apps.apple.com/app/apple-configurator-2/id1037126344)
   (free, Mac App Store).
3. Plug the iPhone into the Mac via USB.
4. Prepare → Manual Configuration → check **Supervise devices**, uncheck
   "Enroll in MDM".
5. Follow the wizard; the iPhone will erase and come back supervised.
6. Download the chosen `.mobileconfig` from the latest release, install
   via Settings.

Free alternatives for supervision: **iMazing Profile Editor** (Mac/Windows),
**cfgutil** (CLI shipped with Apple Configurator 2).

**Option (b) — Side-load TrollBox via SideStore, use the app to generate**

If you want to customise filters beyond the 8 pre-generated combos
without re-downloading each time:

1. Install [SideStore](https://sidestore.io) on the iPhone (no Mac
   required; re-sign runs every 7 days via a free Apple developer account).
2. Install the TrollBox `.ipa` from the latest release via SideStore.
3. Caveat: SideStore strips several entitlements
   (`platform-application`, `managedconfiguration.profiled-access`,
   `persona-mgmt`). `setuid(0)` fails there, so `euid` stays 501 and most
   root-owned paths are unwritable. Per section:
   - ✅ About Device, LocSim, Badge Color, Saved WiFi work
   - ❌ ClearShot, ResSetter persistence, AppRepack, Tweaks native-hook
     install won't work
   - ⚠️ Ad Blocking can **generate** the mobileconfig but not install it
     silently — the app shares it via the share sheet, you install via
     Settings → Profile Downloaded
4. You still need to supervise via Apple Configurator 2 (same procedure
   as option (a)).

Options (a) and (b) are not exclusive. **Option (a) is enough for 95% of
users.**

## Prerequisites

- An iPhone running **iOS 14.0 - 16.6.1**
- [TrollStore](https://github.com/opa334/TrollStore) installed on the
  device via the installer that matches the iOS version:

  | iOS version | Installer |
  |---|---|
  | 14.0 - 15.4.1 | [TrollHelper](https://github.com/opa334/TrollStore) |
  | 15.5 - 15.7.x | [TrollMisaka](https://github.com/straight-tamago/TrollMisaka) |
  | 15.8.x - 16.6.1 | [TrollInstallerDark](https://github.com/rockylabs-dev/TrollInstallerDark) |

## Build

### Via GitHub Actions

Every push rebuilds the `.tipa`, re-fetches StevenBlack, re-merges the
PACs, pre-generates the 8 release `.mobileconfig` files and overwrites the
rolling `latest` release. See `.github/workflows/build.yml`.

### Local build (optional)

macOS with [Theos](https://theos.dev) + iOS SDK 15.5+ in `$THEOS/sdks`:

```bash
make clean
make package FINALPACKAGE=1
```

## Repo layout

```
TrollBox/
├── ClearShot/            (app source — legacy folder name, kept for
│                          bundle-ID + binary name compatibility with
│                          existing installs. All ObjC files for every
│                          section + the main app shell + helpers.)
├── ClearShotModule/      (Control Center "Capture" bundle source)
├── MYbloXX/              (Ad Blocking PACs + mobileconfig templates +
│                          StevenBlack merge scripts)
├── Resources/            (icon-*.png at every iOS size + icon source)
├── docs/                 (per-section implementation notes)
├── .github/              (CI build workflow)
├── Makefile, Info.plist, entitlements.plist, LICENSE, control
```

The architecture stays binary-compatible with the historical "ClearShot"
name — the executable is still called `ClearShot`, the bundle ID is still
`com.rockylabs.clearshot`, so updating from an older build keeps your
NSUserDefaults (Badge Color prefs, ResSetter factor, AppRepack history,
Ad Blocking filter toggles).

## Credits

Short list; the in-app **About** screen has the per-project detail.

| Project | Used for |
|---|---|
| [TrollStore](https://github.com/opa334/TrollStore) by opa334 | Platform-application ecosystem |
| [TrollInstallerDark](https://github.com/rockylabs-dev/TrollInstallerDark) by rockylabs-dev | TrollStore installer for iOS 15.8.x |
| [Andromeda / Geranium](https://github.com/Son3ra1n/Andromeda) by Son3ra1n | LocSim MapKit UI, Supervise, respring, `setuid(0)` pattern, entitlements template |
| [TrollFools](https://github.com/Lessica/TrollFools) by Lessica | Tweaks injection engine (TFInjector / TFMachO / TFCodesign ports) |
| [ResolutionSetterSwift](https://github.com/haoict/ResolutionSetterSwift) by haoict | ResSetter mechanism |
| [NiceBattery](https://github.com/khanhduytran0/NiceBattery) | About Device battery metrics + auto-refresh pattern |
| [MYbloXX for iOS](https://github.com/pegakmupyem/myxxdev) by pegakmupyem | Ad Blocking mechanism + base PACs |
| [StevenBlack/hosts](https://github.com/StevenBlack/hosts) | Fresh blocklists merged into the PACs at build time |
| [Muffinstore](https://github.com/mineek/muffinstore) by mineek | AppRepack mechanism |
| [Cowabunga](https://github.com/leminlimez/Cowabunga) by leminlimez (BadgeChanger by exerhythm) | Badge Color |
| Jaility (haxi0) | `SBDontLockAfterCrash` mechanism migrated into ResSetter |
| [WiFiList](https://github.com/EthanArbuckle/WiFiList) by EthanArbuckle | Saved WiFi plist layout + keychain query inspiration |
| [YTLite](https://github.com/dayanch96/YTLite), [BHInstagram](https://github.com/BandarHL/BHInstagram), [BHTwitter](https://github.com/BandarHL/BHTwitter) | Example tweak sources referenced in the Tweaks section preamble |
| [Apple Configurator 2](https://apps.apple.com/app/apple-configurator-2/id1037126344) | Documented path for non-TrollStore supervision (free, Mac App Store) |
| [c22dev/TrollBox](https://github.com/c22dev/TrollBox) | **App icon** (GPL v3, re-used with attribution) |
| [Claude](https://claude.com) by Anthropic | Development assistance — large refactors, port design, documentation. The author drives the architecture and the testing; Claude writes a lot of the ObjC glue. |

## License

**GNU General Public License v3.0** — see [`LICENSE`](./LICENSE).

## Disclaimer

Provided for personal use, research and accessibility. Some features
(screen capture of other apps' protected content, simulated locations,
supervision toggles, binary modification, downloading older or newer app
versions than your iOS normally allows, revealing stored WiFi passwords)
can violate third-party terms of service and, depending on content and
jurisdiction, local law. Use responsibly on devices you own.
