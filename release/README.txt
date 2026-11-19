HALLOW TOOLKIT - one-click PC tune-up, gaming and clean-up tools for Windows 10/11

HOW TO INSTALL
1. Right-click the zip > Properties > tick "Unblock" > OK  (stops Windows blocking the scripts)
2. Right-click the zip > Extract All
3. Open the extracted folder and double-click INSTALL.bat
4. Open "Hallow Toolkit" from your Desktop or Start menu and click Yes on the admin prompt

If Windows shows "Windows protected your PC", click "More info" > "Run anyway".
It's plain PowerShell - you can open any .ps1 file in Notepad to see exactly what it does.

WHAT'S NEW IN 5.10
- Gaming > Per-game rules (like Process Lasso): pick a game and set its priority, which CPU cores
  it uses (all, first half - the 3D V-Cache cores on most X3D chips -, second half, or all but the
  first core) and a power plan. The tray app applies the rule when the game starts, also to
  anything the game starts later, and puts your power plan back when it closes.

WHAT'S NEW IN 5.9
- Gaming > Pre-game check (also in the tray menu): a quick read-only look before you play -
  Windows updates waiting for a restart, app updates (winget), RAM, free space on your game
  drives, CPU / GPU load and temperature, background apps that get in the way, how old your NVIDIA
  driver is, and whether Hallow Overlay and Clips are running. Each problem has a fix button.
- Tune-up > Scheduled clean-up (off until you turn it on): weekly or monthly at the time you pick,
  with the Quick Clean-up items you tick. If the PC is off then, it runs next time it's on. The
  tray shows what it freed, and the reports are listed under it. Preview shows what it would free
  without deleting anything.

WHAT'S NEW IN 5.8
- Hallow tab > Hallow accent: pick one accent colour for all the Hallow apps (8 colours or your
  own). Apps with "Use the Hallow accent" on switch to it straight away. To use it in the toolkit
  too, pick Tools > Theme > Hallow accent (your current theme stays until you do).
- Crash reports: if the toolkit or its tray app runs into an error nothing else caught, a report
  goes to the crashes folder next to the toolkit (no settings, keys or links in it; newest 20
  kept; nothing is sent anywhere). The next start tells you, with Show details and Open folder.
- Check links: amber "Crashed <when>" with Show for any Hallow app (or the toolkit) that crashed
  in the last 7 days. Older app versions that don't report crashes are simply skipped.

WHAT'S NEW IN 5.7
- Hallow tab > Check links: one green, amber or red line per check for each Hallow app - running,
  answering the other apps (and running the version that's installed), status file fresh, starts
  with Windows, Hallow Mixer's API answers, Overlay can read FPS and the game server, Hub hosts the
  one Hallow icon. One-click fixes where safe: Start it, Turn on Start with Windows (the app's own
  setting), Open settings. Older app versions show amber, never red. No keys or links are shown.
- The tray app runs the same check quietly once a day and pops up only when something is red
  (only if Tray alerts on the Server tab are on).

WHAT'S NEW IN 5.6
- Phone dashboard: when Hallow Remote is installed, a card at the top points to it - Remote is the
  main phone app now (mixer, Hub games with covers, game session, PC stats). The dashboard keeps
  working as before.
- Server tab > Discord posts > Saved clips (off until you turn it on): when Hallow Clips saves a
  clip, the tray app posts it to your channel - the video itself if it's under Discord's 10 MB
  limit, otherwise "<game> - saved a clip". Older clips are never posted, and the webhook link
  stays on this PC.

WHAT'S NEW IN 5.5
- New Hallow tab: a card for each Hallow app (Mixer, Hub, Vault, Overlay, Remote, Clips) that
  shows whether it's installed and running and whether a newer version is out. Open, Install and
  Update get the newest release from GitHub (checksum checked) and install it for you only - no
  admin. Updates are checked at most every 4 hours. The Hallow Mixer card moved here from Server.
- Games > Game save backup: when Hallow Vault is installed it handles your saves - Back up saves
  now offers to open Vault instead and the weekly toolkit backup skips itself. Your older toolkit
  backups are kept.

WHAT'S NEW IN 5.3
- Phone dashboard: a Games section with your recent Hallow Hub games and a Play button for each
  (needs Hallow Hub 1.9 running; games start through Hub, so your Mixer preset and game session apply).

WHAT'S NEW IN 5.2
- Works with Hallow Hub (new app): Hub can turn your game session on when a game starts and off
  when it closes, so Boost apps and High performance power follow your games by themselves.

WHAT'S NEW IN 5.1
- A modern look: rounded tool cards with a soft outline, a rounded highlight with an accent bar
  on the open page in the sidebar, the logo next to the name, and a dark window title bar.

WHAT'S NEW IN 5.0
- A new icon: an orange gear with a tune-up bolt, instead of the plain H. Shortcuts may show
  the old one for a little while until Windows refreshes its icon cache.

WHAT'S NEW IN 4.9
- Phone dashboard: switch Hallow Mixer profiles (needs Hallow Mixer 3.9 with two or more profiles).

WHAT'S NEW IN 4.8
- Server tab > Discord posts: two new switches, both off until you turn them on (needs Hallow
  Mixer 2.7 running). Listening to: posts songs from apps in the mixer's Music channel after 30 s
  of playing (skipped songs and browser videos are never posted). Mic status: posts "Mic muted" /
  "Mic back on" when a change lasts 10 seconds.

WHAT'S NEW IN 4.7
- Phone dashboard: see what's playing on your PC (song or video) with Previous, Play/Pause and
  Next buttons - needs Hallow Mixer 2.5 running.

WHAT'S NEW IN 4.6
- Share your setup now carries your Hallow Mixer settings too: presets, which app goes in which
  channel, ducking, mic mode and your headset and mic EQ. Importing puts the EQ on your own
  headset and mic. Devices, OBS details and saved game levels are never included.

WHAT'S NEW IN 4.5
- Server tab > Hallow Mixer: install (newest release from GitHub, checksum checked) or open
  Hallow Mixer, the free per-app volume mixer - game, chat, music and media on their own faders.
- Phone dashboard: if Hallow Mixer is running, change each channel's level, mute, the mic and
  presets from your phone. The mixer only listens on this PC, behind its own key.

WHAT'S NEW IN 4.4
- Server tab > Discord posts: connect a channel (webhook link) and the tray app posts your game
  sessions and server alerts there. The link stays on your PC and is never shared with your setup.
- Server tab > Phone dashboard: temps, load, what you're playing, servers and drives on your
  phone - read-only, only over Tailscale, behind a private link. The tray app serves it.
- Tray menu > Sleep / shut down timer: 30 min to 3 hours, a warning a minute before, cancel any
  time - and if you're still in a game it waits 15 more minutes.

WHAT'S NEW IN 4.3
- Health tab > Security check (read-only): antivirus on and up to date, firewall, User Account
  Control, old SMB1 file sharing, Remote Desktop, startup programs that are unsigned or run from
  temp folders, programs open to your network, and browser extensions that can read every site.
  Double-click a row to open the right setting. Plus Quick virus scan and Update virus definitions.
- Tools tab > Before / after snapshot: save a list of your apps, startup items, services, scheduled
  tasks and browser extensions, then compare later to see exactly what an installer added.

WHAT'S NEW IN 4.2
- Gaming tab > Game won't launch?: checks for missing runtimes (Visual C++, DirectX, .NET,
  WebView2), switched-off anti-cheat (Easy Anti-Cheat, BattlEye, Vanguard, FACEIT), Windows
  Security's Controlled folder access blocking saves, a pending restart and full drives.
  Fix problems installs or turns back on what's missing.
- Mic tab > Audio switcher: save two setups (e.g. speakers + webcam mic, headset + headset mic) and
  flip between them in one click, from the tray menu, or with Ctrl+Alt+Home.
- Tune-up tab > Windows Update control: pause updates for 7 days, stop Windows replacing your
  drivers, and see update history - what failed and what the error means.
- Games tab > Move Steam games: move games (and their workshop mods) between drives in one go.
- Network tab > Lag under load test: does your ping jump when someone streams or downloads?
  Graded A+ to F, with the fix if it does.
- Clips & screenshots now also finds OBS recordings.

WHAT'S NEW IN 4.1
- Real toggle switches: green = on, grey = off. Every on/off button (weekly clean-up, weekly save
  backup, tray app with Windows, auto update check, server alerts, keep my mic level) shows one,
  and it flips the moment you click.
- Tweaks tab: the tick boxes are now toggle switches showing what's set on this PC right now. A
  switch you've flipped but not applied yet gets a yellow ring and "not applied".
- Tray menu: Game session says when it's ON.

WHAT'S NEW IN 4.0
- Storage tab > Game launcher caches: Steam, Epic, Battle.net, EA, Ubisoft, Riot, GOG, Discord
  and Medal keep web and download caches that grow to GBs. Clear them in one click - games,
  saves, settings and logins are never touched, and open launchers are skipped.
- Gaming tab > Controller check: live buttons, sticks and triggers for Xbox-style controllers,
  stick drift measured at rest, and battery level.
- Tray app: Game priority boost - your game runs at High CPU priority (turn it off in the tray menu).
- Network tab > Saved Wi-Fi passwords: see and copy the password of any network this PC has
  joined. Shown only in that window, never written to the log.
- Fixes: the Mic tab's live meter jumped between empty and full instead of following your voice;
  Monitor CPU/network bars and recorded game-session CPU were rounded to whole numbers.

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

WHAT'S NEW IN 3.0
- Tweaks tab: privacy, quality-of-life and gaming switches with Undo all; debloat; startup manager;
  background services helper.
- Dev tab: port killer, dev cache cleaner, git status of all your projects.
- Game session recording with a chart, game save backup (with weekly auto-backup), old clips finder.
- Game server ping, DNS speed test, benchmark with history, sleep & wake doctor, Disk map.
- Opens about a second faster. First shareable zip with INSTALL.bat.

WHAT'S NEW IN 2.0
- Health tab: crash detective, memory test, drive health, driver age check.
- Games tab: every installed game with size, store and last played.
- Uninstall tab (like Revo): uninstall, then sweep up leftovers - files to the Recycle Bin,
  registry backed up first.
- Tray app: Auto Game Boost and the Ctrl+Alt+End panic key.
- Speed test, apps using the internet, Downloads/project/duplicate cleaners, CPU temperature.

VERSION 1.0
- The first Hallow Toolkit: Tune-up, Monitor, Gaming, Network, Storage and Tools tabs - Quick
  Clean-up, health report, app updates, weekly auto clean-up, live monitor, ping test, biggest
  folders and more.

TIPS
- Start with the Tune-up page > Health report. It only reads, changes nothing.
- Anything that deletes or changes settings asks first.
- Deep Uninstall backs up removed registry keys/services to the "backups" folder.
- Make a restore point (Tools page) before big changes.

UNINSTALL
Delete the folder  %USERPROFILE%\HallowToolkit  and the two "Hallow Toolkit" shortcuts.
If you turned on the weekly clean-up or tray app, turn them off in the toolkit first.
