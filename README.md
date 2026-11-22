# Hallow Toolkit

One-click PC tune-up, monitoring, gaming, clean-up, deep uninstall and driver tools for Windows 10/11. Plain PowerShell + WinForms.

## Install
1. Download **Hallow Toolkit.zip** from the [latest release](../../releases/latest).
2. Right-click the zip, choose **Properties**, tick **Unblock**, then click **OK**.
3. Extract it and double-click **INSTALL.bat**.
4. Open **Hallow Toolkit** from the Desktop or Start menu and click **Yes** on the admin prompt.

The toolkit checks this repo for new releases when it opens and asks before it updates.

## Highlights
- Quick Clean-up, health report, crash detective, RAM/SSD checks
- Live monitor, game boost, game sessions, save backups, server ping
- **Gamer tools:** mouse report rate and keyboard tester, dead pixel and motion / frame-skip tests, ping graph with route to a game server, max refresh rate with a 15-second revert, shader caches for every GPU and Steam game, Windows gaming settings at a glance, verify game files
- **Game-ready check:** one button before you play - Game Mode, GPU scheduling, power plan, Xbox Game Bar captures (they fight Hallow Clips), apps already using the CPU / GPU, Discord hardware acceleration, full-screen optimizations, RAM, drive space and driver age; settings change only when you click a fix
- **Driver check and drive health** (read-only): graphics, chipset, audio and network driver ages with the maker's page; drive wear, temperature and error counters plus how fast each drive is filling up
- **Hallow family:** install, open, update and link-check Mixer, Hub, Vault, Overlay, Remote, Clips, Keys, Guard and Assist, and find the Hallow Shield browser extension in Chrome / Edge / Brave / Opera
- **Per-game rules, background restraint and IdleSaver** (Process Lasso style, opt-in): priority, cores and power plan per game; background apps that hog the CPU lowered while you play (never games, audio/voice apps or Windows); a different power plan while you're away
- **Light and dark mode for all the Hallow apps:** Light / Dark / Same as Windows on the Hallow tab next to the Hallow accent (saved in theme.json); every Hallow app switches live, and each can override it (the toolkit: Tools > Theme > Look); 5.17: number boxes, coloured list cells and accent buttons follow the switch too
- **Hallow Terminal** (5.18): Hallow PowerShell and Hallow Command Prompt for Windows Terminal - Hallow Dark / Hallow Light colour schemes in your accent (every ANSI colour checked for contrast), the Hallow icon, and a fast prompt (folder, git branch and changes, Hallow VPN, the game you're playing, slow / failed commands; about 4 ms per prompt). A `hallow` command talks to the apps: `hallow status`, `hallow vpn on|off|status`, `hallow torrents pause|resume`, `hallow gear`, `hallow open <app>`, `hallow update` (Tab completes). Added as a Windows Terminal fragment from the Hallow tab - your Terminal settings and `$PROFILE` are never touched; Remove deletes only its own files
- Storage scans, disk map, Revo-style deep uninstall with leftovers scan
- Tweaks, startup and services manager, dev toolbox
- **Mic:** quiet in games but fine in Discord? One-click fix for the Windows mic level, default devices, exclusive control and call ducking (understands virtual mics like SteelSeries Sonar), a live meter, and a warning when an app keeps lowering your mic
- **Drivers:** newest motherboard drivers and BIOS from the maker (fully automatic for ASUS), plus Windows Update drivers for any brand

## Releasing
Bump `$AppVersion` in `HallowCore.ps1`, then run `.\Build-Release.ps1 -Publish`.
