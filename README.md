# CapsFlow

Switch keyboard layouts with Caps Lock and see the selected layout in a small, animated overlay.

A native macOS menu bar app with a choice of overlay position and optional launch at login. Requires macOS 14 or later.

## Build and run

With Xcode and XcodeGen installed:

```sh
./scripts/build.sh
```

Open `CapsFlow.app` in the project folder.

## Setup

1. Grant **Accessibility** and **Input Monitoring** permissions in **System Settings → Privacy & Security**. Restart CapsFlow if prompted.
2. Open **System Settings → Keyboard → Text Input → Edit… → All Input Sources** and turn off **Use the Caps Lock key to switch to and from ABC**.
3. Press **Caps Lock** to cycle through your enabled layouts.

Use the menu bar icon to open settings, pause switching, or quit.
