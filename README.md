<p align="center">
  <img src="docs/images/icon.png" width="128" alt="Notch app icon">
</p>

<h1 align="center">Notch</h1>

<p align="center">
  Turn your MacBook's camera notch into a live, interactive surface — like the iPhone's Dynamic Island.
</p>

<p align="center">
  <img alt="Version 1.2.1" src="https://img.shields.io/badge/version-1.2.1-orange">
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-black">
  <img alt="Swift 6 and SwiftUI" src="https://img.shields.io/badge/Swift-6-F05138">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-blue"></a>
</p>

---

Notch lives in the space around your camera. At rest it's just the notch, with a glance of what matters in its "ears" — your battery, a running timer, what's playing. Hover over it and it opens into a panel of widgets you arrange yourself; move away and it tucks back in. When something happens — your AirPods connect, a timer ends, a meeting starts — it springs out to tell you, then gets out of the way.

## Features

**At a glance**
- **Now Playing** from any app — Music, Spotify, browsers, web apps — with controls, a live progress bar, and a switcher when several apps are playing.
- **Volume & brightness** in the notch, replacing macOS's indicator.
- **Devices**: an AirPods-style pop-up when Bluetooth devices connect, with left, right and case batteries.
- **Pop-ups** for plugging in the charger, a finished timer, a starting meeting and a new track.

**Home**
- A grid of **widgets** you drag, resize and arrange: Battery, Timer, Calendar, CPU, GPU, Memory, Temperature, Devices, Notes and Calculator.
- **System stats** with live graphs, sampled only while you're looking.

**Tools**
- **Timer** with an iOS-style ruler, presets and a notification when it ends.
- **Calendar** with the day's events and **Join** for Meet, Zoom, Teams, FaceTime and Webex calls, laid out as a day strip or a month grid beside or above the events.
- **Files**: a shelf to drop files on and drag them out again later.
- **Notes**: quick notes you type right in the notch.
- **Calculator** with a keypad, live results and history.
- **Mirror**: a quick look at your camera.

**Yours to shape**
- Choose which features appear and in what order, the notch's width, corners and accent color, hover delay, animation speed, and which pop-ups show.
- Liquid Glass on macOS 26 and later, Reduce Motion support, and it works on displays without a notch too.

## Screenshots

<table>
  <tr>
    <td><img src="docs/images/calendar.png" alt="Calendar page with a month strip and the day's events"></td>
    <td><img src="docs/images/timer.png" alt="Timer page with a ruler and presets"></td>
  </tr>
  <tr>
    <td><img src="docs/images/notes.png" alt="Notes tab with a list and an editor"></td>
    <td><img src="docs/images/calculator.png" alt="Calculator with a keypad and live result"></td>
  </tr>
  <tr>
    <td><img src="docs/images/airpods.png" alt="AirPods connected pop-up with battery rings"></td>
    <td><img src="docs/images/volume.png" alt="Volume indicator in the notch"></td>
  </tr>
</table>

## Installation

1. Download **Notch-1.2.1.dmg** from the [latest release](../../releases/latest).
2. Open it and drag **Notch** into **Applications**.
3. Open Notch from Applications.

### First launch: "Notch" Not Opened

Notch isn't notarized by Apple yet, so the first time you open it macOS shows **"Notch" Not Opened — Apple could not verify "Notch" is free of malware**. The app is fine; macOS just can't vouch for it. To open it:

1. Click **Done**.
2. Open **System Settings → Privacy & Security** and scroll to the bottom.
3. Next to *"Notch" was blocked to protect your Mac*, click **Open Anyway**, then confirm with your password or Touch ID.

You only need to do this once. The **Open Anyway** button appears for about an hour after the blocked attempt; if it's gone, open Notch again and it'll come back. (Right-click → Open no longer skips this check on recent macOS.)

If you're comfortable with Terminal, this does the same in one step, by removing the "downloaded from the internet" flag:

```bash
xattr -dr com.apple.quarantine /Applications/Notch.app
```

To start Notch when you log in, hover over the notch, right-click it, and turn on **Launch at Login**.

### Permissions

Notch asks for each permission only when a feature first needs it, and every feature can be turned off in Settings.

| Permission | Used for |
|---|---|
| **Accessibility** | Taking over the volume and brightness keys, and keeping the notch clear of apps' menus |
| **Bluetooth** | Showing devices as they connect, with their batteries |
| **Calendars** | Your next events and the calendar page |
| **Camera** | The mirror — only while it's open |
| **Automation** (Spotify, Music) | Playing and pausing those apps from the notch |
| **Notifications** | Telling you when a timer ends |

## Using Notch

- **Hover** over the notch to open it; move away to close it.
- **Right-click** the open notch for **Edit Home**, **Settings…**, Launch at Login and Quit.
- **Edit Home**: drag widgets to move them, drag a corner to resize, tap **−** to remove, **Add Widget** to bring one back.
- **Drag a file** toward the notch to drop it on the shelf.
- **Tap** the timer or calendar widget to open its page.

## Privacy

Everything stays on your Mac. Notch has no accounts, no analytics and no network requests of its own. The camera runs only while the mirror is open, and nothing is recorded. Notes and settings are stored locally in `~/Library/Application Support/com.vinzi.Notch` and the app's preferences.

## Requirements

- macOS 14 Sonoma or later. Liquid Glass appears on macOS 26 and later; earlier versions get the same design with flat, translucent controls.
- Any Mac — MacBooks with a notch get the full experience; other displays get a floating notch at the top of the screen.
- Developed and tested on macOS 27; on earlier versions, features that rely on private macOS behavior (Now Playing, brightness, temperatures, AirPods batteries) are the most likely to differ.

## Building from source

Requires Xcode 27 or later.

```bash
git clone https://github.com/vinzi0812/notch.git
cd notch
open Notch.xcodeproj
```

Choose the **Notch** scheme and press **⌘R**. To sign, pick your own team under *Signing & Capabilities*.

| Command | What it does |
|---|---|
| `⌘U` in Xcode, or `xcodebuild test -scheme Notch -destination 'platform=macOS'` | Runs the test suite (Swift Testing) |
| `Tools/install.sh` | Builds a Release version and installs it to `/Applications` |
| `Tools/make-dmg.sh` | Builds a Release version and packages `dist/Notch-<version>.dmg`; signs, notarizes and staples it when a Developer ID certificate and a notarytool profile are available |
| `swiftc Tools/MakeAppIcon.swift -o /tmp/MakeAppIcon && /tmp/MakeAppIcon Notch/Resources/Assets.xcassets/AppIcon.appiconset` | Regenerates the app icon |

For how it works inside — the panel, the module system, the Now Playing bridge, the widget grid — see **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

## Known limitations

- **Now Playing** relies on private macOS behavior, so a future macOS update could break it; the rest of the notch keeps working.
- **Controlling a web player** (such as a Safari web app) works only while it's the Mac's current player; otherwise Notch offers to open it.
- **Fan speeds** aren't shown: macOS doesn't expose them to apps.
- Notch isn't on the Mac App Store, because Now Playing and the volume keys need access the App Store doesn't allow.

## Changelog

See **[CHANGELOG.md](CHANGELOG.md)** for what changed in each version.

## License

Notch is released under the **[MIT License](LICENSE)**: you're free to use, change and share the code, as long as the copyright notice comes along. The Notch name and app icon aren't covered by the license.
