# DropKeeper – manual QA checklist

Run before every release. Record the macOS version and Mac model.

## Safe test run (development builds)

Debug builds accept launch arguments that keep testing away from your real data: `-dbPath <file>` uses a separate database and a separate defaults suite, `-noLoginItem YES` leaves login items alone, and `-watch <folder>` (only together with `-dbPath`) watches a test folder. With both, onboarding offers the test folder (already watched) instead of the real Downloads, so a first-launch run never asks for or watches Downloads. Nothing in your real database, defaults or login items is touched. A new `-dbPath` file starts like a first launch.

Build the debug app into `build/dd`, then run it:

    xcodegen generate && xcodebuild build -project DropKeeper.xcodeproj -scheme DropKeeper -destination 'platform=macOS,arch=arm64' -derivedDataPath build/dd -quiet
    mkdir -p /tmp/dk-watch
    build/dd/Build/Products/Debug/DropKeeper.app/Contents/MacOS/DropKeeper \
      -dbPath /tmp/dk-test.sqlite -noLoginItem YES -watch /tmp/dk-watch

Quit it from the menu bar item (or Ctrl-C in the terminal) when done.

Release builds ignore these arguments.

## Presentation
The default is "Under the menu bar icon" (the notch is opt-in). All notch checks below require switching Settings > Show new downloads to "Automatically" or "In the notch" first.

- [ ] Notched MacBook, lid open, no external display: the prompt grows out of the notch and the closed notch shows the mark + count while files are scheduled.
- [ ] File name fully visible below the notch (prompt, notice, hover list and error: nothing sits behind the cutout).
- [ ] Hovering the closed notch opens the list; moving away closes it after a moment.
- [ ] Hover while the panel resizes (closed notch → list) does not flicker.
- [ ] Lid closed with an external display: the prompt appears under the menu bar icon.
- [ ] Automatic follows the pointer: with an external display as primary and the lid open, a new download prompts in the notch when the pointer is on the laptop screen, and under the menu bar icon when the pointer is on the external display.
- [ ] An open prompt, notice or error does not jump to the other display when the pointer crosses displays.
- [ ] Automatic with the lid open: the closed notch (mark + count) stays on the laptop screen wherever the pointer is; hovering it opens the list.
- [ ] With "In the notch": prompt in the notch regardless of the pointer. With "Under the menu bar icon": always under the icon, no closed notch.
- [ ] Mac without a notch: the prompt appears under the menu bar icon.
- [ ] Changing displays while a prompt is open moves the prompt to the right place.
- [ ] Full-screen app in front: the prompt and notice still appear.
- [ ] Typing in another app is not interrupted when a prompt appears; after clicking the prompt, ←/→, Return and Esc work.

## Flows
- [ ] Clicking a file name in the prompt or the list opens the file in its default app; Open in the row menu does the same and is disabled when the file and its folder are gone.
- [ ] Browser download (Safari, Chrome, Firefox): exactly one prompt per finished file, none for partial files.
- [ ] Three files at once: one stack, "Apply to all" applies to all three.
- [ ] Esc: the prompt closes; the file gets the default choice after the grace period.
- [ ] Quiet mode: no prompt opens by itself; a dot appears on the menu bar icon; clicking a waiting file in the list (outside its name) or choosing Show prompt in its menu opens the prompt for that file.
- [ ] Close a prompt with Esc, then click that file ("Waiting") in the list outside its name: its prompt opens again. In Quiet mode the next download still doesn't open by itself.
- [ ] A file expires while a prompt is open: after the prompt closes, the notice shows for 2.5 s with Undo.
- [ ] Expiry: the file goes to the Trash, the notice shows for 2.5 s, and Undo puts it back.
- [ ] Two expiries within 2.5 s: one merged notice; Undo restores both.
- [ ] Permanent-delete mode: confirmation on switching; the notice says "Deleted" and has no Undo.
- [ ] Last 10 seconds: an amber countdown in the menu bar (and the closed notch).
- [ ] Sleep the Mac past an expiry: after wake the file is trashed within seconds.
- [ ] Remove Downloads access in System Settings: warning icon in the menu bar and in Settings; "Check again" clears it after granting access.
- [ ] Launch at login toggles in System Settings → General → Login Items.
- [ ] A failed prompt, list or notice action (e.g. Undo after emptying the Trash) shows a short error in the panel (and in the open list); a failed Undo keeps the notice so Undo can be tried again.
- [ ] Onboarding: if adding Downloads fails, an alert explains why.
- [ ] If the engine can't start, an alert says so and DropKeeper quits (no silent menu bar item).

## Accessibility and appearance
- [ ] VoiceOver: the timeline reads "Delete in 1 hour, at …" and can be adjusted with VoiceOver gestures.
- [ ] Reduce Motion: panels fade instead of growing.
- [ ] Light and dark appearance: Settings and onboarding look right; the notch UI is always black.

## Languages
- [ ] English and Czech: no truncated or untranslated text.
