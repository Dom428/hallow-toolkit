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
- **Per-game rules, background restraint and IdleSaver** (Process Lasso style, opt-in): priority, cores and power plan per game; background apps that hog the CPU lowered while you play (never games, audio/voice apps or Windows); a different power plan while you're away
- Storage scans, disk map, Revo-style deep uninstall with leftovers scan
- Tweaks, startup and services manager, dev toolbox
- **Mic:** quiet in games but fine in Discord? One-click fix for the Windows mic level, default devices, exclusive control and call ducking (understands virtual mics like SteelSeries Sonar), a live meter, and a warning when an app keeps lowering your mic
- **Drivers:** newest motherboard drivers and BIOS from the maker (fully automatic for ASUS), plus Windows Update drivers for any brand

## Releasing
Bump `$AppVersion` in `HallowCore.ps1`, then run `.\Build-Release.ps1 -Publish`.
