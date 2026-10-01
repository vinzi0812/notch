# Changelog

All notable changes to Notch. Versions follow [Semantic Versioning](https://semver.org): new features bump the minor version, fixes bump the patch version.

## 1.3.1 — 2026-10-02

### Fixed
- The battery in the ears and widgets shows the real level: while charging it was always drawn full (with a bolt), and on battery it moved in 25% steps. It's now drawn like the menu bar's battery: filled to the exact level, green with a bolt while charging, a plug when connected but not charging, red when low.

## 1.3.0 — 2026-10-01

### Added
- **Calendar layouts:** choose how the calendar page looks in a new **Calendar** tab in Settings, with a live preview: **Day strip** (the month's days in a scrolling row), **Month beside** (a month grid next to the day's events) or **Month above** (a month grid over the events, in a taller notch).

### Changed
- The Calculator's icon is a monochrome calculator glyph like the other icons, instead of the Calculator app's colored icon.
- The Settings window is titled **Notch Settings** instead of the selected tab's name, which read like the notch's own Home page.

## 1.2.1 — 2026-09-28

### Added
- The project is open source under the MIT License.
- `Tools/make-dmg.sh` packages a release disk image (`dist/Notch-<version>.dmg`) with an Applications shortcut, and signs, notarizes and staples it when a Developer ID certificate is available.

### Changed
- **Runs on macOS 14 Sonoma and later** (was macOS 27 only). Liquid Glass is used on macOS 26 and later; earlier versions get the flat, translucent controls from before it.
- The README is rewritten for people using the app (features, screenshots, installation, permissions, privacy); the internals moved to `docs/ARCHITECTURE.md`.

### Fixed
- Right-clicking anywhere in the Files shelf, not only on a file, offers **Clear Shelf** (with how many files it holds).

## 1.2.0 — 2026-09-28

### Added
- **Calculator:** a button beside the camera (with the Calculator app's icon) opens a calculator: type or tap an expression (+ − × ÷, parentheses, %, ^) and see the result as you go; Return keeps it in history and continues from it, clicking a result copies it. A Calculator widget shows the last result.
- **Notes:** a Notes tab with quick notes you type in the notch (first line is the title, pin to keep on top, empty notes are dropped), and a Notes widget for Home. The notch stays open while you type; Esc or clicking elsewhere lets it close.
- **Devices:** when AirPods, Beats, headphones, speakers, keyboards, mice or controllers connect over Bluetooth, the notch pops up with the device springing in and its battery rings filling (left, right and case for AirPods and Beats). A Devices widget lists what's connected with batteries. Needs Bluetooth permission.
- **Volume & brightness in the notch:** the volume, mute and brightness keys show the notch's own indicator (a pop-up with a level bar, or a bar along the bottom of the open notch) instead of macOS's. ⇧⌥ gives quarter steps. Needs Accessibility permission; keys the notch can't act on (an external display's brightness, an output without volume control) still go to macOS.
- **Liquid Glass:** the notch's buttons, chips and widget cards are glass, and a glass pill slides to the selected tab and to the shown player. Emphasized buttons (Done, Join, the chosen timer preset) stay solid, since tinted glass over the black notch loses its color. On screens without a notch, the notch itself is smoked glass instead of black. Settings uses glass buttons and accent swatches.

### Changed
- **New app icon:** "Midnight island" — a graphite tile with the notch opened up, showing a timer ring and music bars.
- The app is no longer sandboxed, so it can take over the volume and brightness keys. Settings, the Home layout and shelf copies move over automatically on first launch.

### Fixed
- The collapsed notch's ears no longer cover the menus of apps whose menu bar reaches the camera (Xcode, say): while such an app's menus are showing, the notch collapses to just the camera housing. In full screen, where the menu bar hides, the ears come back as soon as it slides away. Needs Accessibility permission to read the menu bar.
- The calendar's "Tomorrow" label now counts from the time it's shown for, not always from the current clock.

## 1.1.0 — 2026-09-27

### Added
- **Tabs** in the expanded notch: **Home** and **Files**. The file shelf moved into the Files tab and now holds 12 files; dragging a file onto the notch opens Files automatically from any tab.
- The app's version and build number are shown at the top of the right-click menu.
- **Customizable timer:** tap the timer on Home to open a full-width page with a minute ruler (up to 2 hours) that follows click-drag, flicks and trackpad scrolling, snaps to whole minutes, and makes the tick under the pointer glow. Click and hold for half a second to zoom in and pick 15-second steps. Times of an hour or more show hours (1:30:00) everywhere. While running, the page shows a large countdown with pause and cancel.
- **Mirror:** a camera button (right of the camera housing) opens a live, mirrored camera view in the notch. The camera runs only while the mirror is open; nothing is recorded or saved.
- **Settings window** (right-click the expanded notch → Settings…), laid out like System Settings with toolbar tabs. **Features:** show or hide each feature and drag to reorder them; hidden features leave the ears, Home, the tabs and pop-ups, and Now Playing stops its helper process while hidden.
- **Look settings:** notch width (Compact, Standard, Wide), corner roundness, an accent color for the timer and playback progress, and whether the collapsed notch shows ears. A live preview follows your changes.
- **Behavior settings:** a hover delay slider (0–1 s) before the notch opens (file drags still open it instantly), an on/off switch for each pop-up (charger, timer finished, meeting starting, new track), and an animation speed for the notch's motion.
- **Timer settings:** the timer's length is remembered across launches (set with the ruler or in Settings), four editable preset chips on the timer page, and switches for the finish notification and its sound.
- **Home widgets:** the area under the player is now a grid of widgets (Battery, Timer, Calendar, CPU, GPU, Memory, Temperature) in four sizes: Small, Wide, Tall and Large. The grid has 4, 5 or 6 columns depending on the notch width; widgets that don't fit at a width stay in the layout and return when there's room. There's never empty space: unused columns are dropped and widgets grow into any gap beside them.
- **Calendar page:** tap the Calendar widget to open a page with the month's days in a scrolling strip (dots on busy days) and the selected day's events below, with ‹ › to change month. Events show their calendar's color, time and length or place; click one to open it in Calendar, and calls (Meet, Zoom, Teams, FaceTime, Webex) get a Join button. The bigger Calendar widget sizes list the next few events.
- **Edit Home:** right-click the notch and choose Edit Home (or use Settings → Home): widgets jiggle; drag one to move it, drag its corner to resize, tap − to remove, and Add Widget to bring one back. The notch stays open until Done.
- **System stats:** CPU and GPU usage with a one-minute graph, memory used (with pressure colors), and CPU and battery temperatures. Sampled every 2 seconds, only while a stats widget is on screen.
- **Several players at once:** when more than one app has a track loaded, their icons appear beside the player controls to switch which one the notch shows and controls. Spotify and Music are controlled directly (macOS asks once for permission); other apps that aren't the Mac's current player get an Open button instead of controls that might reach the wrong app.
- Music playing in a web browser (Arc, Chrome, Safari…) shows a music-note tile in the accent color instead of the browser's icon, since macOS doesn't say which site is playing or share its artwork.

### Changed
- Page height changes (switching tabs, the player row appearing or leaving) use a slower, softer spring.
- Now Playing steps out of the ears, and skips the new-track pop-up, while you're in the app that's playing. The player row in the expanded notch stays.

### Fixed
- The timer's notification described short timers as a "0-minute session"; it now spells out the length ("Your timer for 30 seconds is done.").
- Dragging a file out of the shelf and dropping it back no longer adds it twice; the shelf recognizes the same file, including a copy Finder made of it.

## 1.0.0 — 2026-09-27

First version, installed to /Applications.

- The notch overlay: sits on the hardware notch (or a virtual one on other screens), expands on hover, lets clicks through when collapsed, follows display changes.
- **Battery:** level and charging state in the ears; a charging animation with a filling battery when power is connected.
- **Timer:** a 25-minute Pomodoro with play/pause/reset, live countdown in the ears, and a notification when it finishes.
- **Calendar:** the next event; a countdown in the ears from 10 minutes before a meeting and a "Now" pop-up when it starts.
- **File shelf:** drop files or screenshot thumbnails onto the notch; drag them back out; kept across launches.
- **Now Playing** from any app (browsers, web apps, Music, Spotify): the source app in the ears, a player with progress and controls, and a pop-up on track changes.
- Launch at Login and Quit from a right-click menu; Reduce Motion support; app icon.
