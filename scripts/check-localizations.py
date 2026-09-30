#!/usr/bin/env python3
"""Fail if any string in the app's String Catalog lacks a translated Czech value."""
import json
import pathlib
import sys

CATALOG = pathlib.Path(__file__).resolve().parent.parent / "App/Resources/Localizable.xcstrings"


def czech_units(entry):
    cs = entry.get("localizations", {}).get("cs")
    if not cs:
        return []
    if "stringUnit" in cs:
        return [cs["stringUnit"]]
    plural = cs.get("variations", {}).get("plural", {})
    return [variant["stringUnit"] for variant in plural.values()]


def main():
    strings = json.loads(CATALOG.read_text(encoding="utf-8")).get("strings", {})
    missing = []
    for key, entry in sorted(strings.items()):
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        units = czech_units(entry)
        if not units or any(unit.get("state") != "translated" for unit in units):
            missing.append(key)
    if missing:
        print("check-localizations: missing Czech translations:")
        for key in missing:
            print(f"  {key!r}")
        sys.exit(1)
    print(f"check-localizations: OK ({len(strings)} strings)")


if __name__ == "__main__":
    main()
