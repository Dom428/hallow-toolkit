HALLOW TOOLKIT - one-click PC tune-up, gaming and clean-up tools for Windows 10/11

HOW TO INSTALL
1. Right-click the zip > Properties > tick "Unblock" > OK  (stops Windows blocking the scripts)
2. Right-click the zip > Extract All
3. Open the extracted folder and double-click INSTALL.bat
4. Open "Hallow Toolkit" from your Desktop or Start menu and click Yes on the admin prompt

If Windows shows "Windows protected your PC", click "More info" > "Run anyway".
It's plain PowerShell - you can open any .ps1 file in Notepad to see exactly what it does.

WHAT'S NEW IN 3.9.1
- Cleaner buttons: the icon sits in its own column with a gap, the title is bold and the
  description is smaller and dimmer underneath.

WHAT'S NEW IN 3.9
- Apps tab: 103 apps (was 65), each with a one-line reason to get it, in gamer-first groups:
  game launchers, game tools, game runtimes, chat & voice, recording & streaming, browsers,
  music & video, images & 3D, everyday tools, remote help, security & privacy, developer.
- New: Rockstar, itch.io, Prism Launcher, CurseForge, Heroic; HWiNFO, CPU-Z, GPU-Z,
  CrystalDiskInfo/Mark, DDU, NVCleanstall, RivaTuner, Moonlight, Parsec; XNA, PhysX, Java 8,
  .NET 9; Mumble; Streamlabs, Medal, Voicemeeter, EarTrumpet; MPC-HC, Plex, Jellyfin, Kodi;
  Flow Launcher, Revo, Obsidian, Ventoy, Google Drive, Dropbox; Proton VPN, Mullvad, WARP, WireGuard.
- Tick starter pack: Steam, Discord, 7-Zip, VLC and the game runtimes that stop most
  "missing .dll" errors - one click for a fresh PC.

WHAT'S NEW IN 3.8
- New Apps tab - like Ninite, built in: tick the apps you want (browsers, game launchers, Discord,
  OBS, 7-Zip, game runtimes and more) and install them all silently in one go, from each maker's
  official installer. See what's already installed or has an update.
- Search every app in winget and install from the results.
- My apps: save your usual set and tick it all again on a new PC in one click. It goes along with
  Share your setup.
- Open on Ninite: opens ninite.com with the same apps ticked, if you prefer Ninite.

WHAT'S NEW IN 3.7
- New look: Font Awesome icons on every tab, button and section (and in the tray menu).
- Themes: Tools tab > Theme. Pick an accent colour (orange, purple, blue, green, red, pink) and a
  background (Hallow dark, Graphite, Navy, OLED black). Your pick is saved and kept across updates.
- New Server tab: is Radarr, Sonarr, Jellyfin, Plex, qBittorrent, Tailscale... running and answering?
  Add your own servers or websites to watch, see free space on every drive, open or restart apps.
- The tray app checks your servers every 5 minutes and pops up if something goes down (and when
  it's back), or a drive is nearly full. Turn it off on the Server tab.
- Health tab > Boot time: how long Windows takes to start, whether it's getting slower, and which
  apps, drivers or services slow it down.
- Crash detective now says which part crashed each game or app (graphics driver, overlay,
  anti-cheat, the game itself...) and what to do about it, plus which programs froze.

Icons: Font Awesome Free (fontawesome.com) - font under SIL OFL 1.1, icons under CC BY 4.0.
See FontAwesome-LICENSE.txt in the toolkit folder.

WHAT'S NEW IN 3.6
- New Mic tab: quiet in games but fine in Discord? One click sets your mic level, makes it the
  default for games AND calls, stops apps locking it, and stops Windows lowering sounds on calls.
- Works with virtual mics like SteelSeries Sonar: keeps Sonar as your default and fixes the real
  mic behind it.
- Pick your own level per mic (e.g. 65% for a mic on a stand), a live meter showing what games
  hear, and a warning when Discord's auto-adjust keeps lowering your mic.
- Tray app can keep your mic at your level (Mic tab > Keep my mic level).
- Fixed the Tools tab "Fixes" header missing (and a startup error).

WHAT'S NEW IN 3.5
- Tools tab > Quick fixes: audio, Bluetooth, Start search, Microsoft Store, icons & thumbnails,
  clock sync and Windows Update reset.
- Drivers tab: back up all drivers, and remove old driver versions Windows keeps around (often GBs).
- Tray app: warns if your GPU runs hot while gaming, and tells you when a toolkit update is out.
- After an auto-update the toolkit shows what's new.

WHAT'S NEW IN 3.4
- System check now checks every monitor: plugged into the graphics card (not the motherboard)
  and running at its fastest refresh rate.
- Gaming tab: pin your games to the graphics card, a PBO + Curve Optimizer BIOS guide for Ryzen,
  and the NVIDIA shader cache size tip.
- Tweaks > Performance: optimizations for windowed games, and stop uploading Windows updates to
  other PCs.

WHAT'S NEW IN 3.3 (3.3.1: fixes Tweaks switches that change a single setting - they now apply and show correctly)
- Tweaks tab: location, online speech and typing personalization off; clipboard history; seconds
  on the clock; taskbar clean-up (Task View, search icon, Start on the left, Widgets); Edge stops
  running in the background; Fast Startup off; Hibernation off.
- Tweaks tab: see which apps used your camera, mic or location and when; Privacy clean wipes
  recent files, jump lists, Explorer history and clipboard history.
- Tools tab: export your setup to a file and import a friend's.

WHAT'S NEW IN 3.2
- Health tab > System check: BIOS, EXPO, Resizable BAR, Secure Boot, TPM, temps, drives and
  hardware errors in one colour-coded list. Runs by itself after a BIOS update.
- Tune-up tab > App updates: see which apps are out of date, tick them, update silently.
- Gaming tab > Game session: one click closes your Boost apps, switches to High performance and
  pauses Windows Update; End puts it all back. Also in the tray menu.

WHAT'S NEW IN 3.1
- Drivers tab: newest motherboard drivers + BIOS straight from the maker (ASUS fully automatic;
  MSI/Gigabyte/ASRock open the support page), plus Windows Update drivers for any brand.
- Auto update: the toolkit checks for a new version when it opens and asks before updating.

TIPS
- Start with the Tune-up page > Health report. It only reads, changes nothing.
- Anything that deletes or changes settings asks first.
- Deep Uninstall backs up removed registry keys/services to the "backups" folder.
- Make a restore point (Tools page) before big changes.

UNINSTALL
Delete the folder  %USERPROFILE%\HallowToolkit  and the two "Hallow Toolkit" shortcuts.
If you turned on the weekly clean-up or tray app, turn them off in the toolkit first.
