# RIO LIFE OS

A personal **daily-routine planner for Windows** with a fully animated **desktop pet** that lives on your screen edge, reminds you about your tasks, makes you take breaks, and reacts to what you do.

- Smart day planner dashboard (runs locally in an Edge app window)
- Desktop companion: Spider-Man and six other animated characters
- Focus Studio (Pomodoro / Stopwatch / Countdown), push-up tracker, test-prep planning
- Task confirmation card with automatic **Distracted** marking
- Sound effects, break reminders, bedtime nudge, quiet mode
- Pure Windows PowerShell + HTML. **No installer, no Python, no Node, no admin rights.**

> Made by **[Aman-p2p](https://github.com/Aman-p2p)**. Character art and animation frames come from the Spiderman-Pet project (see [Credits](#credits)).

---

## Table of contents

1. [Features](#features)
2. [Requirements](#requirements)
3. [Install](#install)
4. [Daily use and hotkeys](#daily-use-and-hotkeys)
5. [The desktop pet](#the-desktop-pet)
6. [Task confirmation and auto-Distracted](#task-confirmation-and-auto-distracted)
7. [Dashboard](#dashboard)
8. [Sound effects](#sound-effects)
9. [Configuration (`pet.json`)](#configuration-petjson)
10. [Customising: characters, animations, sounds](#customising-characters-animations-sounds)
11. [Project layout](#project-layout)
12. [How it works](#how-it-works)
13. [Troubleshooting](#troubleshooting)
14. [Privacy and security](#privacy-and-security)
15. [Credits](#credits)
16. [Changelog](#changelog)

---

## Features

### Planner dashboard
- Generates a **daily plan** of time blocks (study, C course, C++/Python, subjects, assignments, revision, project, workout, meals, sleep ...).
- **"What kind of day is today?"** picker: normal day, self leave, **test / quiz on a subject**, **project deadline** and more.
- **Upcoming tests** per subject: from 2 days before a test, extra test-prep blocks for that subject are added automatically.
- **Unfinished work carries over** to the next day automatically (also via the arrow button on a block, "Tomorrow" on queue items and the Night shutdown). The C course and assignments are re-planned by the engine.
- **Queue** for work that did not fit into the day.
- **Day rollover at midnight** regenerates the plan without restarting the app.
- Daily score, in-app dialogs (no browser pop-ups) and a **Night shutdown** routine.

### Focus Studio
- **Pomodoro**, **Stopwatch** and **Countdown** with a large animated ring.
- Choose the skill you are working on (C, C++/Python, each subject, assignments, revision, project, other, or **Auto** = follow the current block).
- Time is **logged per skill** and the matching planned block is marked done.
- Study time is not double counted between focus sessions and completed blocks.

### Fitness
- **Push-up counter** with a daily goal (Settings). The pet does push-ups when you press *Pushups +10* and celebrates when you hit the goal.

### Desktop pet
- Seven fully animated characters, **21+ animations each**, rendered with per-pixel transparency and a soft shadow.
- Lives at the **edge of your screen** while you work and never steals keyboard focus.
- Walks, runs, jumps, dances, sits, sleeps and **back-flips** when you are away.
- **Web-shot teleport** for the Spider characters: it shoots a web at a new spot and zips along it.
- Reacts to events: task done, goals, new block, break time, bedtime.
- **Break reminder** after about 50 minutes of real activity, **bedtime nudge**, **quiet mode**.
- Modern **speech cards** (dark card, accent stripe, shadow, fade, message queue).
- Sharp text on scaled displays (per-monitor DPI aware rendering).
- Right-click menu with character switcher, language, sound and reminder toggles.
- **English or Hinglish** pet voice.

### Task confirmation bot
- When a task block ends, a card asks **"Did you finish it?"** with **Done / Need more time / Later**.
- "Need more time" extends the block (+10 / +15 / +20 / +30 / +45 min) and shifts the next blocks.
- No answer for **10 minutes** -> the task is automatically marked **DISTRACTED** and carried over.

### Sound effects
- 16 custom sounds (web shot, zip, landing, jump, wave, pop, alert, chime, done, celebrate, break, sleep, wake, distract, push, snap).
- Replace any sound by dropping a `.wav` with the same name into `sfx\`.

---

## Requirements

| | |
|---|---|
| OS | **Windows 10 / 11** (Windows PowerShell 5.1 is built in) |
| Browser | **Microsoft Edge** (opens the dashboard as an app window) |
| Extras | none: no Python, Node.js or admin rights needed |

The optional `tools\` scripts (to build characters, animations and sounds) need Python 3 with `pillow` and `numpy`.

---

## Install

```text
git clone https://github.com/Aman-p2p/RIO-LIFE-OS.git C:\RIO-OS
cd C:\RIO-OS
install-startup.bat
```

or download the ZIP from GitHub and unzip it to a folder such as `C:\RIO-OS`.

`install-startup.bat`:
1. unblocks the RIO files in the folder (Mark-of-the-Web only for these files),
2. stops any previous RIO instance,
3. creates the tray icon,
4. creates **Startup** and **Desktop** shortcuts named *RIO LIFE OS*,
5. starts RIO, which opens the dashboard and shows the tray icon.

**Update:** back up the folder, copy the new files over the old ones (keep your data), run `install-startup.bat` again.

**Remove:** `install-startup.bat remove` (removes the shortcuts and stops RIO). `stop-rio.bat` only stops it for this session.

---

## Daily use and hotkeys

| Key / action | What it does |
|---|---|
| `Ctrl + Shift + Q` | Show / hide the dashboard |
| `Ctrl + Shift + P` | Show / hide the desktop pet |
| `Ctrl + Shift + R` | Quit RIO (controller and local server) |
| Close the dashboard (X) | RIO keeps running in the tray |
| Tray icon left-click | Show the dashboard |
| Right-click the pet | Pet menu |
| Click the pet | It waves / points and tells you what to do now |
| Drag the pet | Move it; at the edge it remembers its height |

---

## The desktop pet

### Behaviour

| Situation | What the pet does |
|---|---|
| You are working | Peeks from the screen edge (half visible, perched) |
| Idle for about 75 s | Comes to the middle: walks, runs, sits, jumps, dances, waves, flips, stretches |
| You touch mouse / keyboard | Dashes back to the edge |
| Mouse stays near it for 2 s | **Teleports** away (web-shot for Spider characters) |
| Task confirmation open | Thinks and waits |
| Focus session running | Sits quietly, cyan glow, no chatter |
| Full-screen app (video, game, slides) | Hides and waits |
| Bedtime (from your sleep setting) | Gives one gentle nudge, then lies down and sleeps; wakes up with you |
| ~50 min of continuous activity | Suggests a break and stretches |
| Task done / goal reached | Cheers / celebrates |
| Task not answered for 10 min | Marked **Distracted**, pet reacts |
| Pushups +10 | Does push-ups |

The pet speaks only for events (teleport, task start, 5 minutes left, task over, pomodoro done, push-up goal, important meetings, breaks, bedtime). Messages are queued so they never overwrite each other.

### Right-click menu

- Open / hide dashboard
- What should I do now?
- Start / pause pomodoro
- Pushups +10
- **Quiet mode (1 hour)**: no chatter, no roaming, no reminders (task confirmations still appear)
- **Sound effects**
- **Break reminders**
- Always show (even with the dashboard open)
- **Character**: Spider-Man, Tom Holland, Miles Morales, Gwen Stacy, Deadpool, Iron Man, Thor, plus the classic poses and drawn bat
- **Language**: English / Hinglish
- Teleport now, Hide pet, Quit RIO LIFE OS

### Characters and animations

| Character | Animations |
|---|---|
| Spider-Man (`spider_2`) | idle, walk, run, jump, fall, land, climb, swing, hang, perch, sit, stand up, sleep, wake up, wave, dance, celebrate, interact, dragged, wall slide + **thwip, point, stretch, think, cheer** |
| Tom Holland | 14 repo animations + **thwip, point, stretch, think, cheer** |
| Miles Morales | 11 repo animations |
| Gwen Stacy, Deadpool, Iron Man, Thor | 21 repo animations each |

Every character also gets **back-flip** and **push-ups**. If a character does not have an animation, the closest one is used automatically.

---

## Task confirmation and auto-Distracted

1. A planned block ends. The pet shows a card (and the dashboard shows a banner): **"Did you finish it?"**
2. **Done** marks it finished and the pet celebrates.
3. **Need more time** lets you choose +10 / +15 / +20 / +30 / +45 min (custom in the dashboard). The block is extended and the following blocks shift; if there is no room the extra time goes to the queue.
4. **Later** hides the card (the dashboard banner stays).
5. **No answer for 10 minutes**: the dashboard marks the block **DISTRACTED**, the pet tells you, and the unfinished work carries over like any other pending task. The card shows a countdown bar. Marking the block done later removes the Distracted tag.

---

## Dashboard

The dashboard is a single `index.html` served by a tiny local PowerShell server at `http://localhost:5173` and shown in an Edge app window. It covers the planner, focus timers, subjects and upcoming tests, the queue, settings (push-up goal, sleep time and more) and the night shutdown routine. The pet and the dashboard talk through small JSON files (`sync.json`, `cmd.json`) in the RIO folder.

---

## Sound effects

| File | Played when |
|---|---|
| `pop.wav` | normal speech card appears |
| `alert.wav` | important message |
| `chime.wav` | task confirmation card appears |
| `done.wav`, `celebrate.wav` | task done, goals, completions |
| `distract.wav` | task auto-marked Distracted |
| `thwip.wav`, `zip.wav`, `land.wav` | web-shot teleport |
| `jump.wav`, `wave.wav`, `snap.wav` | jump, greeting, stretch |
| `break.wav` | break reminder |
| `sleep.wav`, `wake.wav` | bedtime / waking up |
| `push.wav` | push-ups |

Sounds are silent in quiet mode and full-screen apps, and during focus sessions only alerts, chimes, done, celebrate, distract and break are allowed.

---

## Configuration (`pet.json`)

Created and updated automatically by the pet menu. All keys are optional.

```json
{
  "skin": "spider_2",
  "hidden": false,
  "always": false,
  "lang": "hi",
  "breaks": true,
  "sfx": true,
  "dpi": true,
  "side": "R",
  "peek": 0.55
}
```

| Key | Meaning |
|---|---|
| `skin` | Character folder name in `pets\` (`spider_2`, `tom_holland`, ...), or `spider` / `bat` for the classic looks |
| `hidden` | Start with the pet hidden |
| `always` | Show the pet even while the dashboard is the active window |
| `lang` | `en` (English) or `hi` (Hinglish) pet voice |
| `breaks` | Break reminders on/off |
| `sfx` | Sound effects on/off |
| `dpi` | `true` = sharp rendering on scaled displays. Set `false` if the pet or cards are misplaced on your screen |
| `side` | Screen edge the pet perches on: `R` or `L` |
| `peek` | Height on the edge (0.08 to 0.92 of the screen) |

---

## Customising: characters, animations, sounds

The scripts in `tools\` need `pip install pillow numpy`.

**Add or rebuild characters** from the Spiderman-Pet repo:

```text
python tools\bake_pets.py <path-to>\Spiderman-Pet-main\characters pets [character ids]
```

Each character becomes `pets\<id>\` with one strip PNG per animation and a `pet.json` (frame size, FPS, loop, anchor).

**Build the extra poses** (thwip, point, stretch, think, cheer) for rigged characters, then bake them in:

```text
python tools\make_extra_anims.py <path-to>\Spiderman-Pet-main extras
python tools\bake_pets.py <path-to>\Spiderman-Pet-main\characters pets --extras extras
```

**Regenerate the default sounds:**

```text
python tools\make_sfx.py sfx
```

---

## Project layout

```text
RIO-OS/
|- index.html            dashboard (planner, Focus Studio, settings)
|- server.ps1            local web server (http://localhost:5173)
|- tray.ps1              tray controller + desktop pet + sounds
|- start-rio.vbs         hidden launcher (no console window)
|- install-startup.bat   installer / uninstaller (Startup + Desktop shortcuts)
|- stop-rio.bat          stop RIO for this session
|- pet.json              pet settings
|- rio.ico               icon (generated by the installer)
|- pets/                 characters (sprite strips + pet.json each)
|- sfx/                  sound effects (.wav)
|- tools/                bake_pets.py, make_extra_anims.py, make_sfx.py
`- README.md
```

Runtime files created while RIO runs (`sync.json`, `cmd.json`, `rio-error.log`, your saved data) should not be committed; see `.gitignore`.

---

## How it works

- `start-rio.vbs` launches `tray.ps1` hidden. `tray.ps1` starts `server.ps1`, creates the tray icon and the hotkeys, and opens the dashboard in an Edge app window.
- The pet is a borderless, click-through-where-transparent window that shows a 32-bit ARGB bitmap (per-pixel alpha). Animations are horizontal sprite strips drawn frame by frame at about 20 ticks per second.
- The dashboard writes its state to `sync.json`; the pet reads it for events and the current task, and sends commands (pomodoro, push-ups, task answers) back through `cmd.json`.
- The 10-minute Distracted rule runs inside the dashboard, so it works whenever the dashboard is running (also when its window is closed to the tray).

---

## Troubleshooting

| Problem | Fix |
|---|---|
| No tray icon | Run `install-startup.bat` again and read the installer window for errors |
| Hotkey does nothing | Another app already uses that key combination |
| Pet not visible | It hides while the dashboard is the active window, or in full-screen apps. Click another window, use right-click > Always show, or press `Ctrl+Shift+P` |
| Pet or cards look misplaced on a scaled display | Set `"dpi": false` in `pet.json` and restart RIO |
| No sound | Check Windows volume; sound effects toggle and quiet mode; the `sfx` folder must exist |
| Pet speaks the wrong language | Right-click the pet > Language |
| Something broke after an update | Open `rio-error.log` next to `tray.ps1` and check the last line; run `install-startup.bat` again |
| Port 5173 is in use | Close the other program using it, then restart RIO |

---

## Privacy and security

- The dashboard is served only from `localhost` and the local server accepts same-origin requests only.
- The installer unblocks **only the RIO files in its own folder**. It does not disable Windows Defender, SmartScreen or any global attachment warning.
- Only run the scripts if you trust the source: review `tray.ps1`, `server.ps1` and `install-startup.bat` first.

---

## Credits

- **RIO LIFE OS** by [Aman-p2p](https://github.com/Aman-p2p).
- Animated character art and frames: derived from the **Spiderman-Pet** project (Spider-Man, Tom Holland, Miles Morales, Gwen Stacy, Deadpool, Iron Man and Thor). The rig-based animations (thwip, point, stretch, think, cheer) were authored for RIO on top of that artwork.
- Spider-Man, Deadpool, Iron Man, Thor and related characters are trademarks of their respective owners (Marvel / Disney, Sony). This is a **fan project for personal, non-commercial use**; check the licensing of the artwork before redistributing it or using it commercially.
- Sound effects are synthesised by `tools\make_sfx.py` and can be replaced freely.

---

## Changelog

- **v6**: sharper UI on scaled displays, new animations (thwip, point, stretch, think, cheer, back-flip, push-ups), sound effects, web-shot teleport, auto-Distracted after 10 minutes.
- **v5**: fully animated characters from the Spiderman-Pet repo, character switcher, sleep / wake / sit / dance / jump behaviour.
- **v4**: modern speech cards with queue, redrawn task card, break reminders, bedtime nudge, quiet mode, remembered position, dark menu, Hinglish / English.
- **v3**: real-image Spider pet, smart planner, Focus Studio, push-ups, test-prep planning, auto carry-over, task confirmation bot.
