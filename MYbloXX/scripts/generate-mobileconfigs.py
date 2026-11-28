#!/usr/bin/env python3
"""
generate-mobileconfigs.py — pre-build the 8 mobileconfigs attached to each
TrollBox release. Each file wraps one of the 4 PACs (inlined as a data URL)
plus optionally the tvOS-beta no-OTA payload.

Called from .github/workflows/build.yml AFTER the PACs have been merged
with the day's StevenBlack.

Output filenames (dropped in --output-dir) :

    TrollBoxAdBlock-Standard.mobileconfig
    TrollBoxAdBlock-noFB.mobileconfig
    TrollBoxAdBlock-noXXX.mobileconfig
    TrollBoxAdBlock-noFBnoXXX.mobileconfig
    TrollBoxAdBlock-Standard-noOTA.mobileconfig
    TrollBoxAdBlock-noFB-noOTA.mobileconfig
    TrollBoxAdBlock-noXXX-noOTA.mobileconfig
    TrollBoxAdBlock-noFBnoXXX-noOTA.mobileconfig
"""
import argparse
import base64
import plistlib
import uuid
from pathlib import Path


PAC_MAP = {
    "Standard":   "MYbloXX.pac",
    "noFB":       "MYbloXXnoFB.pac",
    "noXXX":      "MYbloXXnoXXX.pac",
    "noFBnoXXX":  "MYbloXXnoFBnoXXX.pac",
}


def load_template(path):
    with open(path, "rb") as fh:
        return plistlib.load(fh)


def build_mobileconfig(proxy_tpl, tvos_tpl, pac_bytes, label):
    pac_b64 = base64.b64encode(pac_bytes).decode("ascii")
    pac_url = "data:application/x-ns-proxy-autoconfig;base64," + pac_b64

    proxy = dict(proxy_tpl)
    proxy["ProxyPACURL"] = pac_url
    proxy["PayloadUUID"] = str(uuid.uuid4())

    content = [proxy]
    if tvos_tpl:
        tvos = dict(tvos_tpl)
        tvos["PayloadUUID"] = str(uuid.uuid4())
        content.append(tvos)

    return {
        "PayloadType":              "Configuration",
        "PayloadVersion":           1,
        "PayloadIdentifier":        "com.trollbox.adblock",
        "PayloadUUID":              str(uuid.uuid4()),
        "PayloadDisplayName":       f"TrollBox Ad Blocking ({label})",
        "PayloadDescription":       "Blocks ads and trackers system-wide.",
        "PayloadOrganization":      "TrollBox",
        "PayloadRemovalDisallowed": False,
        "PayloadContent":           content,
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pac-dir",   required=True, help="Directory with merged PACs")
    ap.add_argument("--templates", required=True, help="MYbloXX/Templates/ path")
    ap.add_argument("--output-dir", required=True)
    args = ap.parse_args()

    pac_dir = Path(args.pac_dir)
    tpl_dir = Path(args.templates)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    proxy_tpl = load_template(tpl_dir / "proxy-payload.plist")
    tvos_tpl  = load_template(tpl_dir / "tvos-beta-payload.plist")

    for label, pac_name in PAC_MAP.items():
        pac_bytes = (pac_dir / pac_name).read_bytes()
        for ota_suffix, tvos in [("", None), ("-noOTA", tvos_tpl)]:
            cfg = build_mobileconfig(proxy_tpl, tvos, pac_bytes,
                                     label + (ota_suffix.replace("-", " ") if ota_suffix else ""))
            name = f"TrollBoxAdBlock-{label}{ota_suffix}.mobileconfig"
            dst  = out_dir / name
            # plistlib.dumps() writes the XML preamble with SINGLE quotes
            # (<?xml version='1.0' encoding='UTF-8'?>). QuickLook's UTI
            # sniff on iOS is stricter than real profile loading and will
            # occasionally classify a single-quoted preamble as text/xml
            # instead of a config profile — the file then opens as text in
            # Safari / Files instead of triggering Settings → Profile
            # Downloaded. Rewrite the preamble to match Apple's own double-
            # quoted convention.
            raw = plistlib.dumps(cfg, fmt=plistlib.FMT_XML)
            raw = raw.replace(
                b"<?xml version='1.0' encoding='UTF-8'?>",
                b'<?xml version="1.0" encoding="UTF-8"?>',
                1,
            )
            dst.write_bytes(raw)
            print(f"[+] {name}: {dst.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
