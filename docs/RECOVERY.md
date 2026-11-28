# RECOVERY — if TrollBox 2.0.0 left your display unusable

The ResSetter section shipped in 2.0.0 could write a bad resolution the
display can't render. Until a verbatim port of upstream `ResolutionSetterSwift`
lands, ResSetter is **pulled from 2.0.1** and these steps let you recover
from a 2.0.0 brick.

## Symptoms

- After Apply + respring, or after reboot, the display is zoomed / cut off
  so far that you can't reach the passcode digits
- Reset (from ResSetter) does nothing

## Why

- We wrote the gfx plist as XML where IOKit expects binary (silent corruption)
- `writeToURL:` from euid=501 on a root-owned file in
  `/var/mobile/Library/Preferences/` fails silently, so Reset didn't clean up
- The LaunchDaemon re-applied the bad plist at every boot

## Recovery — Voice Control via Siri (preferred, no Mac needed)

1. **"Hey Siri, turn on Voice Control"** (or in French: *Hey Siri, active
   Commande vocale*). Siri activates it from the lock screen without
   needing the passcode.
2. A microphone icon appears at the top of the screen.
3. Say **"Show grid"** (*Afficher la grille*). A numbered grid overlays
   the entire screen, including zones that fell off-screen.
4. For each passcode digit, say **"Tap on <grid number where the digit sits>"**.
   This reaches off-screen areas.
5. Once unlocked, say **"Open TrollBox"**.
6. Navigate inside TrollBox by saying button names
   (**"Tap Reset to native"** / **"Tap Reset + respring"**).
   The reset still won't fully clean the plist (that's the bug) — go to
   the next step.

## Recovery — delete the poison files directly

If Voice Control reaches TrollBox and ResSetter but its Reset does nothing,
use **any TrollStore app with a root file browser** (Filza TrollStore,
Cowabunga, Nugget, SystemBridge, …) to delete these three files, then reboot:

```
/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist
/var/mobile/Library/Preferences/TrollBoxGfxBackup.plist
/Library/LaunchDaemons/com.trollbox.ressetter.plist
```

Reboot (power + home 10 s on SE 1st-gen). Native resolution is restored.

## Recovery — SSH

If TrollStore-OpenSSH is installed:

```sh
ssh mobile@<iphone-ip>        # default password: alpine
su                             # default password: alpine
rm -f /var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist
rm -f /var/mobile/Library/Preferences/TrollBoxGfxBackup.plist
rm -f /Library/LaunchDaemons/com.trollbox.ressetter.plist
reboot
```

## Last resort — DFU + restore via Finder

Only if nothing above is reachable:

1. Try a local backup via Finder before wiping, if the device will trust the
   Mac (requires passcode on first trust — unlikely to help here).
2. DFU mode:
   - iPhone SE 1 / 6s: hold Power + Home ~10 s, keep Home only when screen
     is black until "Recovery" dialog appears on Mac.
3. Finder → iPhone → **Restore iPhone**.
4. Device is wiped and returned to factory iOS 15.8.8.
5. TrollStore, TrollBox and their local data are gone; iCloud-backed data
   returns if a backup exists.
