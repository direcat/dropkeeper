# DropKeeper – manual QA checklist

Run before every release. Record the macOS version and Mac model.

## Safe test run (development builds)

Debug builds accept launch arguments that keep testing away from your real data: `-dbPath <file>` uses a separate database, `-noLoginItem YES` leaves login items alone, and `-watch <folder>` watches a test folder instead of the real Downloads. Nothing in your real database, defaults or login items is touched.

    mkdir -p /tmp/dk-watch
    build/dd/Build/Products/Debug/DropKeeper.app/Contents/MacOS/DropKeeper \
      -dbPath /tmp/dk-test.sqlite -noLoginItem YES -watch /tmp/dk-watch

Release builds ignore these arguments.

## Presentation
- [ ] Notched MacBook, lid open, no external display: the prompt grows out of the notch and the closed notch shows the mark + count while files are scheduled.
- [ ] Hovering the closed notch opens the list; moving away closes it after a moment.
- [ ] Hover while the panel resizes (closed notch → list) does not flicker.
- [ ] Lid closed with an external display: the prompt appears under the menu bar icon.
- [ ] External display as primary with the lid open (Automatic): prompt under the menu bar icon. With "In the notch": prompt in the notch.
- [ ] Mac without a notch: the prompt appears under the menu bar icon.
- [ ] Changing displays while a prompt is open moves the prompt to the right place.
- [ ] Full-screen app in front: the prompt and notice still appear.
- [ ] Typing in another app is not interrupted when a prompt appears; after clicking the prompt, ←/→, Return and Esc work.

## Flows
- [ ] Browser download (Safari, Chrome, Firefox): exactly one prompt per finished file, none for partial files.
- [ ] Three files at once: one stack, "Apply to all" applies to all three.
- [ ] Esc: the prompt closes; the file gets the default choice after the grace period.
- [ ] Quiet mode: no prompt opens by itself; a dot appears on the menu bar icon; clicking a waiting file in the list opens the prompt.
- [ ] Expiry: the file goes to the Trash, the notice shows for 2.5 s, and Undo puts it back.
- [ ] Two expiries within 2.5 s: one merged notice; Undo restores both.
- [ ] Permanent-delete mode: confirmation on switching; the notice says "Deleted" and has no Undo.
- [ ] Last 10 seconds: an amber countdown in the menu bar (and the closed notch).
- [ ] Sleep the Mac past an expiry: after wake the file is trashed within seconds.
- [ ] Remove Downloads access in System Settings: warning icon in the menu bar and in Settings; "Check again" clears it after granting access.
- [ ] Launch at login toggles in System Settings → General → Login Items.
- [ ] An error from a prompt or list action is visible to the user (currently only shown in Settings — note what happens).

## Accessibility and appearance
- [ ] VoiceOver: the timeline reads "Delete in 1 hour, at …" and can be adjusted with VoiceOver gestures.
- [ ] Reduce Motion: panels fade instead of growing.
- [ ] Light and dark appearance: Settings and onboarding look right; the notch UI is always black.

## Languages
- [ ] English and Czech: no truncated or untranslated text.
