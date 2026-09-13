<!doctype html>
<html>
<head>
<style>
body { font-family: system-ui, sans-serif; line-height: 1.6; max-width: 900px; margin: 40px auto; padding: 0 20px; background: #0b0b0b; color: #c2c2c2; }
h1 { color: #ebebeb; border-bottom: 2px solid #303030; padding-bottom: 10px; }
h2 { color: #ebebeb; margin-top: 40px; }
h3 { color: #c2c2c2; margin-top: 20px; }
.section { border-left: 3px solid #4d4d4d; padding-left: 20px; margin: 30px 0; }
.critical { border-left-color: #a87676; }
.feature { border-left-color: #7d9b7d; }
.qa { border-left-color: #7a7a7a; }
code { background: #1a1a1a; padding: 2px 6px; border-radius: 3px; font-family: monospace; color: #ebebeb; }
li { margin-bottom: 8px; }
ul ul { margin-top: 8px; }
</style>
<title>Neutrino — Future Work & Feature Ideas</title>
</head>
<body>

<h1>Neutrino — Future Work & Feature Ideas</h1>
<p><em>Personal-use optimizations, new features, and architecture improvements for a single-user desktop shell.</em></p>

<hr>

<h2>🔴 Critical Fixes (Do These First)</h2>

<div class="section critical">

<h3>PpdProfile Singleton Not Resolving</h3>
<p><strong>Status:</strong> Blocks power profile switching<br>
<strong>Root cause:</strong> <code>ReferenceError: PpdProfile is not defined</code> in shell.qml:703</p>

<p>Quickshell's singleton pattern may require:</p>
<ul>
<li>Explicit <code>pragma Singleton</code> + registration in root component</li>
<li>Different instantiation (like how <code>UPower</code>, <code>Bluetooth</code> are exposed)</li>
<li>Import via <code>Quickshell</code> namespace</li>
</ul>

<p><strong>Fix:</strong> Check Quickshell docs or examine how built-in singletons (UPower, Bluetooth) are exposed, then apply same pattern.</p>

<h3>Missing Error States</h3>
<p>Power profile, network, Bluetooth currently crash silently when DBus isn't responding. Add fallback UI:</p>
<ul>
<li>Greyed-out buttons instead of crashes</li>
<li>"Service unavailable" status lines</li>
<li>Retry logic on DBus reconnect</li>
</ul>

</div>

<hr>

<h2>🏗️ Architecture Improvements</h2>

<div class="section">

<h3>1. Split shell.qml (2704 lines → 3 files)</h3>
<p>Extract into:</p>
<ul>
<li><code>ControlCentre.qml</code> (400 lines) — all CC pages, entries, submenu logic</li>
<li><code>BarModules.qml</code> (350 lines) — 18 module declarations + widgetItems registry</li>
<li><code>shell.qml</code> (200 lines) — screen loop, theme, global state</li>
</ul>
<p><strong>Payoff:</strong> Each file readable; easier to add/modify modules and pages.</p>

<h3>2. Flyout Auto-Generation</h3>
<p>Replace 14 identical <code>FlyoutPanel { scope; flyout; ... }</code> declarations with a Repeater. Adding a flyout = 1 line of config. Saves 100 lines of boilerplate.</p>

<h3>3. Settings Field Builder</h3>
<p>Pattern <code>SettingsField { label; hint; YourControl {} }</code> repeats 50+ times. Create a <code>SettingControl</code> component. Input.qml, Audio.qml, Display.qml drop 30% boilerplate.</p>

<h3>4. Constants Singleton</h3>
<p>Extract magic numbers (barHeight, radiusOuter, animFast, panelBg color, etc.). Single place to tweak the entire look. Easier to test themes.</p>

<h3>5. Service Layer Pattern</h3>
<p>Wrap system calls (DBus, Hyprland IPC, files) in a <code>Services.qml</code> singleton:</p>
<ul>
<li><code>Services.powerProfile.set(name)</code> instead of scattered code</li>
<li><code>Services.bluetooth.scan()</code>, <code>pair(device)</code></li>
<li><code>Services.wallpaper.set(path)</code></li>
</ul>
<p>Easier to test, mock, or swap backends.</p>

</div>

<hr>

<h2>✨ New Features (Prioritized by Usefulness)</h2>

<div class="section feature">

<h3>Tier 1: High Value, Medium Effort</h3>

<p><strong>1. Workspace Quick-Switch Overlay</strong><br>
SUPER+W → grid of all workspaces with current windows. Click to jump. Drag windows between workspaces. Show window count per workspace.</p>

<p><strong>2. Custom Quick Actions</strong><br>
Let user define their own QA row buttons (run command, toggle app). Store in Settings.json. Drag-to-reorder. Optional: icon picker with system icons.</p>

<p><strong>3. Per-App Window Rules</strong><br>
Flyout to set: always float, always tile, start on workspace X, start fullscreen. Store in hyprland.lua comments or separate config. Preview matched windows as you type app name.</p>

<p><strong>4. Night Light Sunrise/Sunset Auto</strong><br>
Calculate sunrise/sunset for your location. Auto-enable at sunset, disable at sunrise. Fallback: manual time range (6pm–7am).</p>

<p><strong>5. Do Not Disturb Schedule</strong><br>
Set DND to auto-enable at night, auto-disable at morning. Exceptions: allow calls from starred contacts (if swaync supports it).</p>

<p><strong>6. Workspace Naming</strong><br>
Name workspaces (Work, Gaming, Social, etc.). Show names in workspace switcher and bar. Auto-jump by name: SUPER+G → Gaming workspace.</p>

<h3>Tier 2: Nice-to-Have, Lower Effort</h3>

<p><strong>7. Screenshot/Recording Preview</strong><br>
Show last screenshot in a corner widget. Click to open in feh/zathura. Hotkey to copy last screenshot again.</p>

<p><strong>8. Keyboard Layout Indicator</strong><br>
Show current XKB layout in bar (US, DE, etc.). Click to cycle to next layout. Populate from <code>kb_variant</code> already in Input page.</p>

<p><strong>9. VPN Status Module</strong><br>
Watch <code>wg-quick</code> or <code>openvpn</code> status. Show connected/disconnected state. Quick toggle button.</p>

<p><strong>10. CPU Temp in Bar</strong><br>
Already reading it in System window. Add a compact bar module (show only if hot, e.g., &gt;70°C).</p>

<p><strong>11. Git Status in Terminal/Prompt</strong><br>
Already have starship.toml integration. Add git branch to bar title when a terminal is focused.</p>

<p><strong>12. Floating Window Grouping</strong><br>
When 3+ floating windows open, auto-stack them (tile in a grid). Hotkey to toggle between grid and cascade. Option to auto-grid only windows from same app.</p>

<p><strong>13. Media Player Integration</strong><br>
Already have Media module reading D-Bus. Add: next/prev/pause/play buttons to lock screen. Show album art as wallpaper (optional, neat easter egg).</p>

<p><strong>14. System Tray Icons with Right-Click</strong><br>
Right-click opens a menu from their context. Let user un-pin apps from tray.</p>

<p><strong>15. Notification History Panel</strong><br>
Sidebar showing last 20 notifications. Click to re-open/action them. Search by app or text.</p>

<h3>Tier 3: Fun/Polish, Low Priority</h3>

<p><strong>16. Weather Forecast in Lock Screen</strong><br>
Show 3-day forecast. Use color-coded icons (rainy = blue, sunny = yellow).</p>

<p><strong>17. System Uptime in Lock Screen</strong><br>
Show uptime before login (useful for debugging crashes).</p>

<p><strong>18. Daily Affirmation / Quote of the Day</strong><br>
Fetch from a simple API on startup. Show in lock screen or splash screen. Cache for offline use.</p>

<p><strong>19. Focus Mode / Distraction-Free</strong><br>
Hide all bar modules except clock + battery. Mute notifications except alarms. Hotkey to toggle. Auto-revert after N minutes or on window blur.</p>

<p><strong>20. App Launcher Search Ranking</strong><br>
Weight recent apps, starred apps, frequency. Learn from user behavior (ML-lite: JSON with launch counts).</p>

<p><strong>21. Workspace per Monitor</strong><br>
Currently all screens share workspaces. Option to isolate workspaces per display. Useful if you have external monitor and laptop screen.</p>

<p><strong>22. Custom Color Scheme Editor</strong><br>
Graphical picker for the grayscale ramp. Live preview on bar/flyouts. Export to theme file.</p>

<p><strong>23. Sound Visualizer Improvements</strong><br>
Make it optional in Quick Actions. Add frequency bands instead of just spectrum. Sync to music beat (if MPD/playerctl available).</p>

<p><strong>24. Keyboard Shortcuts Cheat Sheet</strong><br>
Pop-up (SUPER+?) listing all binds by category. Search by command name. Update from hyprland.lua automatically.</p>

</div>

<hr>

<h2>🎯 Personal-Use Optimizations (You Only)</h2>

<div class="section qa">

<h3>Single-User Advantages</h3>

<p><strong>1. Auto-Login & Auto-Start</strong><br>
Skip password on boot. Auto-launch preferred apps. Restore previous workspace layout.</p>

<p><strong>2. Performance Tweaks</strong><br>
Aggressive caching (wallpaper palette, weather, monitor info) to disk. Lazy-load Settings pages. Preload frequently-used singletons on startup.</p>

<p><strong>3. Dev-Friendly Shortcuts</strong><br>
SUPER+E → open nvim with git root. SUPER+T → new terminal in current dir. SUPER+F → fzf file picker in current workspace.</p>

<p><strong>4. Auto-Save Everything</strong><br>
Settings auto-save on every change. Automatically backup Settings.json daily. Keybinds auto-sync to a git hook (commit hyprland.lua on change).</p>

<p><strong>5. Personal Dashboard</strong><br>
Replace System window with a personal status board:</p>
<ul>
<li>Upcoming calendar events (if you use one)</li>
<li>Todo list (if you use one)</li>
<li>RSS feeds / Hacker News top stories</li>
<li>Git repo status (dirty repos, open PRs)</li>
</ul>

<p><strong>6. Aggressive Personalization</strong><br>
Color scheme per time of day. Font size that scales with time. Auto-switch to "reading mode" when System idle &gt;5min.</p>

</div>

<hr>

<h2>📊 Code Quality & Testing</h2>

<div class="section">

<p><strong>1. QML Unit Tests</strong><br>
HyprBinds.js → 30+ test cases. HyprTables.js → 20+ test cases. Run via qmltestrunner in CI.</p>

<p><strong>2. Error Logging</strong><br>
Add a Debug.qml singleton. Write to ~/.local/state/quickshell/debug.log. Offer a "Export Debug Logs" button in System window.</p>

<p><strong>3. Settings Migrations</strong><br>
Version field in Settings.json. Auto-upgrade on load. Backup old settings before migrating.</p>

<p><strong>4. Keybinds Validation on Boot</strong><br>
Check for duplicates / conflicts with Hyprland reserved binds. Warn in log if found.</p>

</div>

<hr>

<h2>🔮 Wild Ideas (Very Low Priority)</h2>

<ul>
<li><strong>Gesture support</strong> — swipe up = Super, swipe left = workspace -1</li>
<li><strong>Voice control</strong> — SUPER+V to launch a voice command</li>
<li><strong>Ambient lighting</strong> — sync keyboard RGB to wallpaper color</li>
<li><strong>Smart standby</strong> — suspend when you leave, wake on motion</li>
<li><strong>Habit tracking</strong> — track which apps you use, suggest breaks</li>
<li><strong>Pomodoro timer</strong> — integrated in bar, auto-mute notifications during focus</li>
</ul>

<hr>

<p><em>Last updated: 2026-09-12</em></p>

</body>
</html>