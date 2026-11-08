RIO LIFE OS - detached hidden-launcher build (v6: sharp UI, more animations, sound effects, web-shot teleport)

INSTALL / UPDATE
1. Back up your existing C:\RIO-OS folder.
2. Unzip this package into C:\RIO-OS and let it overwrite: tray.ps1, index.html, pet.json, README.txt, plus the 'pets' and 'sfx' folders.
   (The 'pets' folder now holds one sub-folder per character; the old spider-1.png / spider-2.png files can stay.)
   server.ps1 is unchanged.
   Keep start-rio.vbs, install-startup.bat and stop-rio.bat as they are.
3. Run install-startup.bat once. It stops the old controller and starts the new one.
   Your data (tasks, C course progress, settings) is kept; new fields are added automatically.

LAUNCH / WINDOWS
- Startup and Desktop shortcuts target wscript.exe, which runs start-rio.vbs.
- The Edge app dashboard opens visibly on startup. The RIO tray icon stays in the notification area.

NEW IN v6
- Sharp message cards: RIO now draws the pet, the speech cards and the task box at your screen's real
  resolution, so text is no longer stretched / pixelated on scaled displays (125%, 150% ...).
  If anything is misplaced on your screen, set "dpi": false in pet.json to go back to the old mode.
- New animations (Spider-Man and Tom Holland): thwip (web shot), point, stretch, think, cheer.
  Everyone also gets a back-flip and push-ups (the pet does push-ups when you press Pushups +10).
    stretch ... break reminder      point ..... "what should I do now?" / task cards
    think ..... waits while the task-over question is open     cheer ..... task done, goals
- Web-shot teleport (Spider characters): instead of shrinking away, the pet shoots a web at the new spot
  and zips along it, then lands. Other characters keep the poof teleport.
- Auto 'Distracted': when a task ends the pet asks "Did you finish it?". If nobody answers within
  10 minutes (the card shows a countdown bar) the dashboard marks that task DISTRACTED, tells the pet,
  and the unfinished work carries over like any other pending task. Needs the new index.html.
- Sound effects (folder 'sfx'): thwip, zip, land, jump, wave, pop, alert, chime, done, celebrate, break,
  sleep, wake, distract, push, snap. Right-click pet > Sound effects turns them on/off. Silent in quiet mode,
  during full-screen apps and (except alerts) during focus sessions.
  Make your own: drop a .wav with the same name into 'sfx' (or run tools\make_sfx.py to regenerate defaults).
- tools\make_extra_anims.py builds the new poses for any rigged character from the repo.

NEW IN v5 (animated characters from the Spiderman-Pet repo)
- The pet is now a fully animated character instead of two still poses. Seven characters ship in the
  'pets' folder (Spider-Man, Tom Holland, Miles Morales, Gwen Stacy, Deadpool, Iron Man, Thor).
  Pick one with right-click pet > Character.
- Real animation for every situation:
    peeking at the screen edge ........ perch
    you are away / roaming ............ walk, run, idle, sit down and stand up again
    you come back ..................... runs back to the edge
    bedtime ........................... lies down and sleeps (fully visible), wakes up when you do
    click the pet ..................... waves (and shows what you should do now)
    task done / goal reached / new block  celebrate / wave
    random while roaming .............. jump + land, dance, wave
    dragging it ....................... dragged pose
    focus session ..................... sits quietly with a cyan glow
  Characters with fewer animations automatically use the closest one (Spider-Man has all 21).
- The pet greets you with a wave the first time it appears after RIO starts.
- Add more characters from the repo: python tools\bake_pets.py <repo>\characters pets <character-id>
  (needs: pip install pillow). Each character becomes pets\<id>\ with one strip PNG per animation.
- Default look is spider_2 (Spider-Man). The old two-pose Spider and the drawn Bat are still available under
  Character > Classic.
- The pet's own lines default to Hinglish (matches your dashboard messages). Right-click > Language > English.

NEW IN v4 (pet UI + behaviour)
- Speech cards: modern dark card with accent stripe, optional title, soft shadow, smooth fade in/out,
  per-pixel alpha (no more jagged magenta edges). Click a card to dismiss it.
- Message queue: events no longer overwrite each other. Normal messages wait their turn (max 4);
  important ones interrupt; idle chatter never interrupts anything.
- Task confirmation card: redrawn from scratch (rounded, shadow, slide + fade in, hover highlight,
  hand cursor). Same Done / Need more time / Later flow as before.
- Break reminder: after about 50 minutes of real keyboard/mouse activity the pet suggests a short break
  (never during focus sessions, full-screen apps or quiet mode). Toggle: right-click pet > Break reminders.
- Bedtime nudge: once per evening, right when your sleep time (from the dashboard) starts.
- Quiet mode: right-click pet > Quiet mode (1 hour). No chatter, no roaming, no reminders.
  Task-time confirmations still appear.
- Remembers where you parked it: drag the pet up/down at the screen edge and it stays there next time
  (side and height are saved in pet.json).
- Hover reaction: the pet grows slightly when your mouse is close; softer gradient ground shadow.
- Dark right-click menu with grouped sections, check marks, Look and Language sub-menus.
- Language: English by default. Right-click pet > Language > Hinglish restores the old Hinglish lines.
- pet.json now also stores lang, breaks, side, peek (all optional; old pet.json files still work).
  Note: the pet.json in this package selects the Spider look (the Spider PNGs are what ship with RIO).

If something looks wrong after updating, open rio-error.log (next to tray.ps1) and send me the last line.

REAL-IMAGE PET (v3)
- The pet now uses real PNG images (pets\spider-1.png = swing pose, pets\spider-2.png = crouch/web pose)
  on a true per-pixel-alpha window, so edges are smooth and nothing but the character is clickable.
- Animations: breathing + idle sway, leans toward your mouse, crossfade between the two poses with a pop,
  swing pose + web line hanging from above while it roams, squash & stretch jumps with random
  back-flips, speed ghost trail while dashing back to the edge, ground shadow, cyan aura during
  focus sessions, sleepy dim + floating z Z, spin-and-shrink teleport with ring burst,
  and a random "thwip" web shot from its hand while it peeks at the screen edge.
- Add your own character: put <name>-1.png (swing) and <name>-2.png (crouch) in the pets folder
  (transparent PNG, about 300 px tall). Optional <name>.json sets the display scale and the hand
  anchors where the web starts: {"scale":0.5,"aHand":[0.96,0.07],"bHand":[0.97,0.06],"bShoot":[0.21,0.19]}
  (numbers are fractions of the image width/height). For the bat look use the name 'bat'.
  If the PNGs for a look are missing, the old drawn pet is used for that look.

CONTROLS
- Ctrl+Shift+Q: show/hide dashboard.
- Ctrl+Shift+P: show/hide the desktop pet.
- Ctrl+Shift+R: quit the RIO controller and local server for this session.
- Closing the dashboard (X / Alt+F4) keeps RIO alive in the tray; use Ctrl+Shift+Q to show it again.

DESKTOP PET (Spider-style / Bat-style)
- Right-click the pet: Open dashboard, What should I do now, Start/pause pomodoro, Pushups +10,
  Hide/Show pet, Look: Spider-style / Bat-style, Teleport now, Always show, Quit.
- While you are working (mouse/keyboard active) the pet stays at the side of the screen, half visible,
  gripping the edge and peeking. It does not cover your work and never takes keyboard focus.
- If you do nothing for ~75 seconds it comes to the middle of the screen, walks, jumps and plays.
  The moment you touch the mouse/keyboard it dashes back to the edge.
- If your mouse stays near the pet for 2 seconds it teleports far away from the mouse
  (mouse low -> pet goes high, mouse high -> pet goes low) with a poof animation.
- It does not chatter. It speaks only for events: teleport, task start, 5 minutes left,
  task time over, pomodoro done, pushup goal, important meetings.
- During full-screen apps (video, games, presentations) the pet hides and waits.
- During a pomodoro / stopwatch / countdown session it stays quiet at the edge.
- Pet choices (look, hidden, always show) are saved in pet.json.

TASK CONFIRMATION BOT
- When a task block ends, a small box appears bottom-right (and a banner in the dashboard):
  "Mark this task as done?"
    Done            -> task marked done, pet tells you what is next.
    Need more time  -> choose +10/+15/+20/+30/+45 (or custom in dashboard); the block is extended
                       and the following blocks shift. If there is no room, the extra time goes to the queue.
    Later           -> hides the box (the dashboard banner stays until you answer).

NEW IN THE DASHBOARD
- Focus Studio: Pomodoro, Stopwatch and Countdown with a bigger animated ring.
  Choose the skill you are working on (C, C++/Python, each subject, assignments, revision, project, other,
  or Auto = follow the current block). Time is logged per skill and matching planned blocks are marked done.
- Pushups replaced water (daily goal in Settings).
- "What kind of day is today?" is now pick-one. New types: Self leave, Test / quiz on a subject
  (choose the subject), Project deadline. Subjects page has "Upcoming tests": from 2 days before, extra
  test-prep blocks for that subject are added automatically.
- Unfinished work carries over to the next day automatically (also via the arrow button on a block,
  "Tomorrow" on queue items, and Night shutdown). C course and assignments are re-planned by the engine itself.
- Prompts and alerts are now in-app dialogs instead of browser pop-ups.

BUG FIXES
- Tray icon left-click handler used the wrong event argument and never fired; fixed.
- Day study time no longer double-counts focus sessions and completed blocks.
- Sync file is written atomically; sync endpoint only accepts same-origin posts.
- Pet commands are queued, so two quick clicks no longer overwrite each other.
- Day rollover at midnight now regenerates the plan without restarting the app.

SECURITY
- Installer unblocks only RIO files in this folder. It does not disable Windows Defender,
  SmartScreen or global attachment warnings. Only run the scripts if you trust the source.

TROUBLESHOOTING
- No tray icon: run install-startup.bat again and read the installer window for errors.
- Hotkeys fail: another app already uses that key combination.
- Pet not visible: it hides while the dashboard is the active window. Click another window,
  or use right-click -> Always show. Check Ctrl+Shift+P if you hid it.
- Speech is silent: check Windows volume and installed speech voices. RIO still works without speech.
