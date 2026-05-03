Hyprland Easy Layout

This script fixes the common problem where Hyprland apps open in a random order or wrong size when you first log in. It waits for each app to fully load before moving and resizing them, so your desktop looks perfect every time.
✨ What it does

Wait for Apps: It waits until an app is actually visible before trying to move it.

Perfect Groups: Automatically puts apps (like Discord and Spotify) into tabbed groups.

Exact Sizes: You set the size by percentage (like 80% width), and the script does the math for you.

One Workspace at a Time: It sets up one workspace before moving to the next to prevent glitches.

📂 Where to put it

Put the files in your Hyprland folder like this:
Plaintext

~/.config/hypr/
├── autostart.conf        # The script creates this for you
└── layout/
    ├── layout.sh         # The script
    ├── layout.conf       # Your layout rules
    └── layout.log        # Check here if something goes wrong

🛠 How to use
1. Define your apps

Open layout.conf and list your apps.
Format: APP <name> <window_class> <launch_command>
Plaintext

APP nvim  org.omarchy.nvim  alacritty --class org.omarchy.nvim -e nvim

2. Set your rules

Tell the script where you want the apps to go.
Plaintext

# Put nvim on workspace 1, move it right, and make it 80% wide
RATIO 1 nvim  r  100% 80%

# Group these apps on workspace 10
GROUP 10 beeper discord spotify

3. Save and Sync

Run this command in your terminal to update your Hyprland autostart:
Bash

chmod +x layout.sh
./layout.sh --generate

💬 Requirements

    jq and awk (usually already on your system).

    uwsm (if you use it to launch apps).

⚖️ License

MIT
