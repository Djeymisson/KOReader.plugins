# KOReader FileBrowser Shortcut ![Version](https://img.shields.io/badge/version-v1.0.7-blue)

A lightweight shortcut for **KOReader** that starts and stops the Kindle
「网页文件管理器 2」(Web File Browser 2) from inside KOReader, so you can
wirelessly send books and manage files from a browser **without leaving
KOReader**.

## Features

- One-tap **Start / Stop** of the「网页文件管理器 2」service from the KOReader
  menu (Tools → 网页文件管理器 2). KOReader stays in the foreground; it never
  drops back to the Kindle home screen and never writes to the framebuffer.
- The device IP is shown right next to the **Start** menu item, and shown
  centered in a popup when already running, so you always know where to point
  your browser.
- **No second FileBrowser install**: instead of bundling or running its own
  `filebrowser` binary, the plugin reuses the one already provided by the
  KUAL extension「网页文件管理器 2」. Extra footprint is just a shortcut.
- Easy transfer: once running, open `http://<device-IP>` in any browser on
  the same Wi-Fi to upload, download and manage files on the Kindle — no USB
  cable needed.
- A **Status / IP / About** menu entry shows the runtime state, the device IP,
  and the upstream open-source project links.

## Requirements (important)

This plugin is **only a shortcut** — it does **not** include the core program.
Before using it, you must have installed:

1. A jailbroken Kindle with the **KUAL** launcher.
2. The KUAL extension **「网页文件管理器 2」** (provides the `filebrowser`
   binary): <https://github.com/Gh9518/kindle-filebrowser-optimized>
3. **KOReader** itself.

If the dependency is missing, tapping **Start** clearly tells you how to
install it instead of failing silently.

## Installation

1. Download `kofb.koplugin.zip` from the Releases page and extract it.
2. Copy the resulting `kofb.koplugin/` folder into KOReader's plugins directory:

   ```text
   koreader/plugins/kofb.koplugin/
   ```

3. Restart KOReader.

## Usage

- **Tools → 网页文件管理器 2**:
  - **Start**: launches the service in the background (KOReader stays in front).
    The menu item shows the device IP; tapping again while running shows the
    current IP centered.
  - **Stop**: stops the service and reports success or failure.
  - **Status / IP / About**: shows runtime state, device IP, and upstream
    project links.
- You can also bind **Start / Stop / Status·IP** to gestures, hardware keys,
  or the quick panel via KOReader's Dispatcher.

## How it works

The plugin ships a small `fb_bridge.sh` bridge script that only does three
things: keep the screen awake, open port 80, and launch the existing
`filebrowser` binary in the background — reusing the KUAL extension's core
program and database. It does **not** return to the home screen, does **not**
write to `eips`, does **not** touch the wireless switch, and does **not** start
the screen-writing watchdog, so it stays fully decoupled from KOReader's
foreground and survives future KUAL extension upgrades.

## Source

<https://github.com/Gh9518/kofb.koplugin>
