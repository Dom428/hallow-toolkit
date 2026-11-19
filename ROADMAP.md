# Hallow Toolkit roadmap

## Done

| Version | What it added |
|---|---|
| **3.2** | System check, app updates, game session |
| **3.3** | Privacy and quality-of-life tweaks, Share your setup |
| **3.4** | Display check, games on the RTX, performance switches |
| **3.5** | Quick fixes, driver backup and clean-up, tray alerts |
| **3.6** | Mic tab: fixes a quiet mic in games |
| **3.7** | Font Awesome icons, themes, Server tab, boot time, crash culprits |
| **3.8** | Apps tab: install apps in one go with winget |
| **3.9** | 103 apps with a reason for each, gamer-first groups, starter pack; cleaner tool buttons |
| **4.0** | Launcher cache cleaner, controller check, game priority boost, saved Wi-Fi passwords |
| **4.1** | Real toggle switches that show whether each setting is on |
| **4.2** | Game launch fixer, audio switcher, Windows Update control, Steam mover, lag test |
| **4.3** | Security check and before/after snapshot |
| **4.4** | Discord posts, phone dashboard, sleep/shutdown timer |
| **4.5** | Hallow Mixer card and mixer controls on the phone dashboard |
| **4.6** | Share your setup carries Hallow Mixer settings |
| **4.7** | Now playing on the phone dashboard |
| **4.8** | Discord posts: listening to and mic status (opt-in) |
| **4.9** | Switch Hallow Mixer profiles from the phone dashboard |
| **5.0** | New icon |
| **5.1** | Modern look: rounded nav, dark title bar, new icons |
| **5.2** | Game session modes for Hallow Hub |
| **5.3** | Start Hallow Hub games from the phone dashboard |
| **5.5** | Hallow tab: install, open and update every Hallow app; save backups hand over to Hallow Vault |
| **5.6** | Phone dashboard points to Hallow Remote; Discord posts for saved Hallow Clips clips (opt-in) |
| **5.7** | Check links: is every Hallow app running and linked, with one-click fixes; daily tray check |
| **5.8** | One Hallow accent colour for all the apps; crash reports kept on this PC, crashes in Check links |
| **5.9** | Pre-game check (Gaming tab and tray); scheduled clean-up with reports (opt-in) |
| **5.10** | Per-game rules: priority, CPU cores and power plan while a game runs |

## Next

### Fixes from real use
- Whatever comes up with the new look, game sessions from Hub and the phone dashboard

### 5.11 - App updates and startup impact
- App updates like UniGetUI: every winget upgrade with its own Update button, Ignore (and un-ignore), nothing runs until you click
- Startup apps show their impact (High / Medium / Low) from what they cost at sign-in

### 5.12 - System info, debloat presets, browser clean-up
- System info page: CPU, GPU, RAM sticks and speed, motherboard, BIOS, drives with SMART health where Windows can read it
- Tweaks presets in WinUtil style (Minimal / Gamer / Privacy): they only flip listed switches, Apply and Undo all work as before
- Browser clean-up per browser (cache, history), opt-in, only while that browser is closed, with a preview

### Gaps vs CCleaner / Revo / Process Lasso
What those tools (and Ninite / UniGetUI, WinUtil, HWiNFO) do that the toolkit didn't, as of 5.9:
- Per-game priority / CPU cores / power plan rules (Process Lasso) - **buildable**: 5.10
- Per-app update list with Ignore (UniGetUI) - **buildable**: 5.11 (the toolkit already lists winget updates and updates ticked apps)
- Startup impact rating (Task Manager / CCleaner) - **buildable**: 5.11, estimated from CPU time and boot-slowdown events
- System summary with RAM sticks, BIOS and drive health (HWiNFO summary) - **buildable**: 5.12
- Debloat / tweak presets (WinUtil) - **buildable**: 5.12, on top of the existing switches and Undo
- Browser cache / history / cookies cleaning (CCleaner) - **buildable**: 5.12 for cache and history; cookies left out on purpose (signs you out everywhere)
- ProBalance - automatically lowering background apps that hog the CPU (Process Lasso) - **buildable later**: needs careful tuning so it never touches games or audio
- IdleSaver / power plan switch when you're away (Process Lasso) - **buildable later**
- Live sensors for every voltage, fan and per-core temperature (HWiNFO) - **not here**: needs a kernel driver; the toolkit shows GPU via nvidia-smi and CPU temp through LibreHardwareMonitor if you install it
- Raw SMART attributes for every drive (HWiNFO / CrystalDiskInfo) - **partly**: Windows only exposes health, wear, temperature and error counters (shown in 5.12)
- Install tracing - log everything an installer changes so it can be undone exactly (Revo) - **not here**: needs file-system and registry monitoring while the installer runs; the toolkit's leftover scan covers most of it
- Registry cleaner (CCleaner) - **not building**: little real benefit and a real risk of breaking apps
- Driver updater for every device (CCleaner Pro) - **not here**: no safe public source; the toolkit uses Windows Update drivers and the board maker's (ASUS) list
- Scoop / Chocolatey / pip / npm sources (UniGetUI) - **not building**: winget covers the apps people install; the others need their own package managers
- Windows ISO builder (WinUtil MicroWin) - **not here**: image servicing of a Windows ISO is a different tool

### Later
- Drivers: fully automatic for MSI and Gigabyte boards, like ASUS today
- BIOS 2503 for this PC: on hold
