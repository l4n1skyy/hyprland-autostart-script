### Hyprland Easy Layout

This script fixes the common problem where Hyprland apps open in a random order or wrong size when you first log in. It waits for each app to fully load before moving and resizing them, so your desktop looks perfect every time.


## ✨ What it does
- Wait for Apps: It waits until an app is actually visible before trying to move it.
- Perfect Groups: Automatically puts apps (like Discord and Spotify) into tabbed groups.
- Exact Sizes: You set the size by percentage (like 80% width), and the script does the math for you.
- One Workspace at a Time: It sets up one workspace before moving to the next to prevent glitches.

## 📂 Where to put it

Put the files in your Hyprland folder like this:

```
~/.config/hypr/
├── autostart.conf        # The script creates this for you
└── layout/
    ├── layout.sh         # The script
    ├── layout.conf       # Your layout rules
    └── layout.log        # Check here if something goes wrong
```

## 🛠 How to use

### 1. Define your apps
Open layout.conf and list your apps.

list current running app classes  ``` hyprctl clients -j | jq -r '.[] | "\(.class) -> \(.title)"' ```

format  ``` APP <alias> <class-name> <launch-command> ```

example
```
APP spotify  Spotify                              spotify
APP todoist  chrome-app.todoist.com__app-Default  chromium --app=https://app.todoist.com/app --user-data-dir="/home/l4n1skyy/.config/todoist-app"
APP obsidian obsidian                             obsidian
APP cbonsai  cbonsai-term                         alacritty --class cbonsai-term -e cbonsai -i -l
APP zen      zen-browser                          zen-browser
```

### 2. Set your rules

```
# LAYOUT RULES
# GROUP <workspace> <alias>
# SPAWN <workspace> <alias>
# RATIO <workspace> <alias> <directions> <y_percent> <x_percent>
# FOCUS <workspace> <alias>
```
example
```
# --- WORKSPACE 10: SOCIAL ---
GROUP 10 beeper discord spotify
FOCUS 10 beeper

# --- WORKSPACE 9: PRODUCTIVITY ---
GROUP 9 obsidian todoist calendar
FOCUS 9 obsidian

# --- WORKSPACE 2: BROWSING ---
SPAWN 2 zen

# --- WORKSPACE 1: THE DASHBOARD ---
RATIO 1 nvim        r       100%   80%
RATIO 1 timr        l,u     20%    20%
RATIO 1 cbonsai     l,d     80%    20%
FOCUS 1 nvim
```

### 3. Save and Sync

Run this command in your terminal to update your Hyprland autostart:
```
chmod +rwx layout.sh
./layout.sh --generate
```

## 💬 Requirements
- jq and awk (usually already on your system).
- uwsm (if you use it to launch apps).


## ⚖️ License
MIT
