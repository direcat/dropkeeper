# DropKeeper – manual QA checklist

Run before every release. Record the macOS version and Mac model.

## Safe test run (development builds)

Debug builds accept launch arguments that keep testing away from your real data: `-dbPath <file>` uses a separate database and a separate defaults suite, `-noLoginItem YES` leaves login items alone, and `-watch <folder>` (only together with `-dbPath`) watches a test folder. With both, onboarding offers the test folder (already watched) instead of the real Downloads, so a first-launch run never asks for or watches Downloads. Nothing in your real database, defaults or login items is touched. A new `-dbPath` file starts like a first launch. Debug builds use the bundle id `net.direcat.dropkeeper.debug`, so they have their own settings and folder permissions and never replace the installed app. Without `-dbPath` a Debug build still opens the real database and may register itself as a login item, so always pass `-dbPath` and `-noLoginItem YES`.

Build the debug app into `build/dd`, then run it:

    xcodegen generate && xcodebuild build -project DropKeeper.xcodeproj -scheme DropKeeper -destination 'platform=macOS,arch=arm64' -derivedDataPath build/dd -quiet
    mkdir -p /tmp/dk-watch
    build/dd/Build/Products/Debug/DropKeeper.app/Contents/MacOS/DropKeeper \
      -dbPath /tmp/dk-test.sqlite -noLoginItem YES -watch /tmp/dk-watch

Quit it from the menu bar item (or Ctrl-C in the terminal) when done.

Release builds ignore these arguments.

## Presentation
The prompt always appears under the menu bar icon, as its own floating card (no popover arrow); one card at a time.

- [ ] Lid closed with an external display: the prompt appears under the menu bar icon.
- [ ] Any Mac model, with or without a notch cutout: the prompt appears under the menu bar icon.
- [ ] An open prompt, notice or error does not jump to the other display when the pointer crosses displays.
- [ ] Changing displays while a prompt is open moves the prompt to the right place.
- [ ] Full-screen app in front: the prompt and notice still appear.
- [ ] Typing in another app is not interrupted when a prompt appears; after clicking the prompt, ←/→, Return and Esc work.
- [ ] Opening the list while a prompt is showing hides the prompt; there is only ever one card on screen.

## Flows
- [ ] Clicking a file name in the prompt or the list opens the file in its default app; Open in the row menu does the same and is disabled when the file and its folder are gone.
- [ ] Browser download (Safari, Chrome, Firefox): exactly one prompt per finished file, none for partial files.
- [ ] Three files at once: one stack, "Apply to all" applies to all three.
- [ ] Esc: the prompt closes; the file gets the default choice after the grace period.
- [ ] Quiet mode: no prompt opens by itself; a dot appears on the menu bar icon; clicking a waiting file in the list (outside its name) or choosing Show prompt in its menu opens the prompt for that file.
- [ ] Close a prompt with Esc, then click that file ("Waiting") in the list outside its name: its prompt opens again. In Quiet mode the next download still doesn't open by itself.
- [ ] A file whose timer is not longer than the reminder lead time (or with reminders off) expires while a prompt is open: after the prompt closes, the notice shows for 2.5 s with Undo.
- [ ] Expiry after a reminder (reminders on, timer longer than the lead time): the file goes to the Trash with no notice; Put back in History restores it. Expiry with reminders off (or a timer not longer than the lead time): the notice shows for 2.5 s and Undo puts it back.
- [ ] Two unreminded expiries (reminders off) within 2.5 s: one merged notice; Undo restores both.
- [ ] List row menu → Move to Trash: the file goes to the Trash at once and the notice with Undo appears; in permanent-delete mode the item reads "Delete Permanently", asks for confirmation (Cancel keeps the file), and the notice has no Undo; disabled when the file is gone. Also try Delete from the list (not only the prompt); the confirmation alert must come to the front.
- [ ] Permanent-delete mode: confirmation on switching; the notice says "Deleted" and has no Undo.
- [ ] Last 10 seconds: an amber countdown in the menu bar.
- [ ] Sleep the Mac past an expiry: after wake the file is trashed within seconds.
- [ ] Remove Downloads access in System Settings: warning icon in the menu bar and in Settings; "Check again" clears it after granting access.
- [ ] Launch at login toggles in System Settings → General → Login Items.
- [ ] A failed prompt, list or notice action (e.g. Undo after emptying the Trash) shows a short error in the panel (and in the open list); a failed Undo keeps the notice so Undo can be tried again.
- [ ] Onboarding: if adding Downloads fails, an alert explains why.
- [ ] If the engine can't start, an alert says so and DropKeeper quits (no silent menu bar item).

## 1.1 features
- [ ] Unified panel under the menu bar icon: a reminder, a rule notice and "Moved to Trash" show as bars above the prompt (the prompt keeps focus; Return and the arrow keys still act on the prompt); bars stack without flicker and the panel resizes smoothly.
- [ ] Quiet mode: reminders and rule notices still show (they do not open a prompt by themselves) and the menu bar dot behaves as before.
- [ ] Rules: enable Installers, download a matching file; it skips the prompt, a notice names the rule and Change reopens the prompt. First match wins; Move up / Move down change the outcome; a disabled rule never matches.
- [ ] Rules on Desktop: with Desktop watched, a screenshot matches Screenshots on Desktop; with Desktop not watched, the rule row in the Rules tab shows an orange hint that the folder isn't watched and the rule does nothing.
- [ ] Duplicate prompt: download the same file twice into one folder; the prompt shows "Same as …" and Delete duplicate removes the new copy; with duplicate detection off in Settings, no such offer.
- [ ] Reminder: with the default 5 minutes, a file scheduled for longer than the lead time (e.g. 30 min) shows a reminder shortly before expiry; Extend adds the timer length, Keep keeps it, Delete now trashes it at once (with Undo). Turned off in Settings: no reminder.
- [ ] Last chosen time: set Default action to Last chosen time (Settings > Expiry), then pick 1 day on one file; the next prompt preselects 1 day and Return applies it.
- [ ] Settings tabs: eyeball the full-width tab bar (General, Folders, Expiry, Rules, Data, About) and that the window opens centered every time, also after moving it and on a second display.
- [ ] Settings sliders: time values change with the slider and the value label updates; ignored file patterns can be added and removed.
- [ ] Upgrade 1.0 to 1.1: with a 1.0 database and defaults that have ignored extensions (e.g. pdf), launch 1.1; they appear in Ignored files as `*.pdf` together with the default patterns (`~$*`, `#*#`, `*~`), and every other setting is unchanged.
- [ ] Ignored patterns: a file named `~$report.docx` or `notes.txt~` in a watched folder gets no prompt.

## 1.2 features
- [ ] Hide notifications after: with the default 30 s the prompt shows "Hides in N s · stays in the list", hides on its own and the file stays in the list. Never keeps it open; 5 s hides it quickly.
- [ ] Pointer resting over the prompt while reading: it never hides while hovered; leaving starts the remaining time, not a full new one.
- [ ] Keyboard-only user picks a time with the arrows after 25 s: the countdown restarts on the key press; with VoiceOver running nothing auto-hides.
- [ ] Open the list while a prompt is showing, then close it: the panel hides while the list is open and does not reappear for files already decided from the list; a still-pending file shows its prompt again only if it was not timed out or dismissed.
- [ ] Menu bar list card: Esc and a click outside close it; clicking the menu bar icon while it is open closes it (the card itself and its menus do not count as outside). Clicks in the gaps between separate cards (list, prompt, notice) do not act on anything.
- [ ] Settings and Onboarding: the content sits below the titlebar and traffic lights and nothing is clipped at the bottom, in Light and Dark.
- [ ] Appearance Dark while macOS is Light (and back to Auto): panel, list, Settings and onboarding all switch immediately, without a restart.
- [ ] History shows the last 10 decisions; Put back restores a trashed file and its row changes to Kept. Put back for a file whose Trash copy was already emptied shows the error in the panel ("couldn't put back"), the row stays and nothing crashes.
- [ ] A file put back from the Finder Trash by hand (not via Put back) does not appear in History.
- [ ] Statistics (Settings > Data) show the counts and space freed since the oldest entry in history; removing a watched folder with many files adds nothing to History or to Kept.
- [ ] Rules reorder by dragging as well as with Move up / Move down.
- [ ] Upgrade from 1.1 (also with the old display-mode setting set to a non-default choice): every setting is kept, the notification timeout is 30 s, Appearance is Auto, and a 1.1 database opens with its old history rows still shown in History and Statistics.
- [ ] Quit while a download is still growing, let it finish, start DropKeeper: it prompts for that file once; a file that vanished meanwhile leaves no trace.

## Accessibility and appearance
- [ ] VoiceOver: the timeline reads "Delete in 1 hour, at …" and can be adjusted with VoiceOver gestures.
- [ ] VoiceOver: the time sliders in Settings read their label and value and can be adjusted; the rule rows' Move up and Move down actions are announced and work.
- [ ] Keyboard focus: every new control (segmented control, "•••" buttons, Decide, Put back, Settings tab bar) shows a visible focus ring in Light and in Dark.
- [ ] Reduce Motion: panels fade instead of growing.
- [ ] Light and dark appearance: Settings and onboarding look right; the panel, the list, Settings and onboarding follow the Appearance setting (see 1.2 features).

## Languages
- [ ] English, Czech, German, Spanish and French: no truncated or untranslated text.
- [ ] Settings > Language: choosing a language shows the restart hint; Restart DropKeeper relaunches in that language; System restores the system language.
- [ ] After choosing a language and before restarting, the UI may mix languages until Restart; Restart reopens DropKeeper in the chosen language; if the relaunch fails the app quits and the language applies on the next launch.
