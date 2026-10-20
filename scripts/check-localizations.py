#!/usr/bin/env python3
"""Fail if any string in the app's String Catalogs lacks a translated value for a supported language."""
import json
import pathlib
import sys

RESOURCES = pathlib.Path(__file__).resolve().parent.parent / "App/Resources"
CATALOGS = [RESOURCES / "Localizable.xcstrings", RESOURCES / "InfoPlist.xcstrings"]
LANGUAGES = {"cs": "Czech", "de": "German", "es": "Spanish", "fr": "French"}


def units(entry, language):
    localization = entry.get("localizations", {}).get(language)
    if not localization:
        return []
    if "stringUnit" in localization:
        return [localization["stringUnit"]]
    plural = localization.get("variations", {}).get("plural", {})
    return [variant["stringUnit"] for variant in plural.values()]


def main():
    strings = {}
    for catalog in CATALOGS:
        strings.update(json.loads(catalog.read_text(encoding="utf-8")).get("strings", {}))
    failed = False
    for language, name in LANGUAGES.items():
        missing = []
        for key, entry in sorted(strings.items()):
            if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
                continue
            found = units(entry, language)
            if not found or any(unit.get("state") != "translated" for unit in found):
                missing.append(key)
        if missing:
            failed = True
            print(f"check-localizations: missing {name} ({language}) translations:")
            for key in missing:
                print(f"  {key!r}")
    if failed:
        sys.exit(1)
    print(f"check-localizations: OK ({len(strings)} strings, {', '.join(LANGUAGES)})")


if __name__ == "__main__":
    main()
