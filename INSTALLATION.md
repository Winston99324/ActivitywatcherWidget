# Installation Guide

Build and install ActivityWatch Widget on your Mac, then add the application and Chrome widgets to your desktop.

## 1. Prepare your Mac

You need:

- macOS 14 Sonoma or later.
- Xcode with the macOS 14 SDK or later. Xcode 15 is the baseline; the project was verified with Xcode 27.1.
- A valid Apple signing identity available in Xcode.
- ActivityWatch installed and running, including its window and AFK watchers.

Open Xcode once and finish any first-launch setup. In Xcode Settings → Accounts, sign in to the Apple account associated with your signing team.

Open `http://localhost:5600` in your browser. Confirm that ActivityWatch shows recent activity. Grant any Accessibility permissions requested by the ActivityWatch watcher. This companion app reads existing records; it does not replace the watchers.

## 2. Download or clone the project

On the GitHub repository page, choose **Code → Download ZIP** and extract it, or use **Code → Open with GitHub Desktop** to clone it.

Open the folder containing `ActivityWatchWidget.xcodeproj`, `App`, `Widget`, and `Config`. Double-click `ActivityWatchWidget.xcodeproj`.

No XcodeGen installation or external Swift packages are required.

## 3. Configure signing

1. Select the **ActivityWatchWidget** scheme and **My Mac** destination.
2. Open `Config/Project.xcconfig` and replace the blank `DEVELOPMENT_TEAM` value with your Apple Developer Team ID. Alternatively, select the same team in **Signing & Capabilities** for both the host app and widget extension targets.
3. Let Xcode resolve any signing-certificate issues before continuing.

The shared configuration starts with:

```xcconfig
DEVELOPMENT_TEAM = YOUR_TEAM_ID
ACTIVITY_APP_GROUP = $(DEVELOPMENT_TEAM).com.example.ActivityWatchWidget.shared
APP_BUNDLE_IDENTIFIER = com.example.ActivityWatchWidget
```

Replace `YOUR_TEAM_ID` with the actual Team ID; it is not your email address. You may change `APP_BUNDLE_IDENTIFIER` to your own reverse-domain identifier. The widget extension automatically adds `.Widget`.

Both targets must use the same App Group. The supplied team-prefixed macOS group is defined in this one shared configuration setting and referenced by both entitlements and Info.plists. If you use a registered `group.…` identifier instead, configure and enable it for both targets.

This project's shared storage setup requires proper signing. An unsigned build or **Sign to Run Locally** is not the supported installation method. Signing credentials are not included in the repository.

## 4. Build and try the app

Press **Command-R** to build and run.

In the dashboard:

1. Click **Find Sources**.
2. Select the window source for this Mac if it is not selected automatically.
3. Select the AFK source from the same computer when using **Exclude idle time**.
4. Click **Save & Refresh**.

Check that today's application totals appear. With idle exclusion enabled, periods without matching active AFK records are excluded.

## 5. Install a signed Release build

Open Terminal in the project folder and run:

```sh
TEAM_ID=YOUR_TEAM_ID bash Scripts/build.sh signed
```

Replace `YOUR_TEAM_ID` with your real Team ID. The script uses your existing signing identity and prints the full path to the built **ActivityWatch Widget.app**. If signing assets are missing, resolve them in Xcode first.

1. Quit the test app and stop its run in Xcode.
2. In Finder, press **Command-Shift-G** and paste the containing folder from the printed build path.
3. Copy the complete **ActivityWatch Widget.app** into `/Applications` or your user Applications folder (`~/Applications`).
4. Launch that installed copy once.

The widget extension is inside the app bundle. Do not install or move the `.appex` separately.

The script builds in a temporary directory by default. Copy the app to Applications before temporary files are removed. You can override the build destination with `BUILD_DIR` and the Xcode location with `DEVELOPER_DIR`.

To locate an app built directly in Xcode, expand **Products** in the project navigator, right-click the app, and choose **Show in Finder**. The selected build configuration determines whether that copy is Debug or Release.

**You can now close Xcode.** Keep the installed app's menu bar updater and ActivityWatch running for regular updates. Closing the dashboard window keeps the updater running; choosing **Quit** stops it.

## 6. Add the desktop widgets

1. Right-click the desktop on the display where you want the widget.
2. Choose **Edit Widgets**.
3. Search for **ActivityWatch Widget** or **ActivityWatch Today**.
4. Add the application activity widget in your preferred size.

If desktop widgets are hidden, check **System Settings → Desktop & Dock → Widgets**.

For a second monitor, open Edit Widgets on that display and place the widget there.

## 7. Connect two Chrome profiles

Install **ActivityWatch Web Watcher** separately in both Chrome profiles. Configure distinct custom browser names, such as `chromework` and `chromepersonal`, while keeping the same computer hostname.

Then select the two corresponding sources in the app, save, and add **Chrome Web Activity** from Edit Widgets. Right-click that widget → **Edit Widget** to choose **Profile 1**, **Profile 2**, or **Combined**, and **Page Titles** or **Websites**.

Follow the [complete Chrome setup guide](CHROME-SETUP.md) for the exact extension settings. Existing history collected into a shared source cannot be reliably separated afterward.

The widget displays page titles and domains, not page bodies or conversation text. Ambiguous profile activity remains unassigned, so browser totals can be lower than the application's Chrome total.

## 8. Optional: launch at login

Enable **Open at login** after moving the app to its permanent Applications location. If macOS requests approval, check **System Settings → General → Login Items**.

ActivityWatch must also start independently. This setting only starts the companion app.

## Updates and refresh timing

The host fetches about once per minute while running and requests automatic widget reloads at most once every five minutes. The widget also requests a new timeline after five minutes, but macOS controls when updates happen. Refresh is not guaranteed while the Mac sleeps.

For an immediate data check, open the dashboard and click Refresh. A successful dashboard fetch does not guarantee an immediate desktop redraw.

To install a newer build, quit the installed app, build the updated project, replace the app in Applications, and launch it again. Keeping the same bundle and App Group identifiers preserves the existing shared settings location. Avoid leaving multiple installed copies with the same bundle identifier.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Widget missing from Edit Widgets | Install and launch the complete signed app. Confirm both targets use the same team and the app contains its widget extension. Reopen the gallery; if needed, log out and back in. |
| Shared storage unavailable | Confirm the Team ID is set and both targets resolve the same App Group. Rebuild both targets together. |
| Cannot connect | Confirm ActivityWatch is running and its dashboard opens at the configured local address. API-key-protected servers are not supported by this version. |
| No application activity | Check that the window watcher is recording and has its required permissions. Choose the correct source for this Mac. |
| Active time is zero | Check the AFK watcher. Temporarily turn off idle exclusion to compare foreground time. |
| Chrome source missing | Save the extension settings and browse a regular page in that profile. Confirm its hostname matches the window source. |
| Widget looks out of date | Check the host's fetched time and latest watcher record. Keep ActivityWatch and the updater running; WidgetKit may delay redraws. |
| Signing reports resource fork or Finder information | Build in a fresh temporary folder or Xcode's default DerivedData location outside cloud-synced folders. The supplied script uses a temporary folder. |

## Compile-only verification

If you only want to check whether the source compiles:

```sh
bash Scripts/build.sh verify
```

This disables code signing. It does not produce a supported installation or verify desktop widget registration.

See [BUILD-VERIFICATION.md](BUILD-VERIFICATION.md) for checks already performed and [README.md](README.md) for architecture, privacy, and tests. Signed desktop registration, login behavior, and use with your actual Chrome profiles still need to be checked on your Mac.
