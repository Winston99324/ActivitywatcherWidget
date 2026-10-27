# Two Chrome Profiles: Set Up the Second Widget

The project includes two independent widgets:

- **ActivityWatch Today**: application usage time.
- **Chrome Web Activity**: page titles, websites, and today's browsing time. Choose Profile 1, Profile 2, or Combined.

Profiles are the separate Chrome profiles available through the avatar menu. You do not need to provide a Google email address, password, or account authorization. The widget displays page titles and websites; it does not read page bodies or conversations, or generate AI summaries.

## 1. Configure the extension in each Chrome profile

Open a window for your first Chrome profile and install the official [ActivityWatch Web Watcher](https://chromewebstore.google.com/detail/activitywatch-web-watcher/nglaklhklhcoonedhgnpgddginnjdadi). Open its settings and use the values below. Repeat in your second Chrome profile.

| Extension setting | First profile, such as Work | Second profile, such as Personal |
| --- | --- | --- |
| Browser | `Other...` | `Other...` |
| Custom browser name | `chromework` | `chromepersonal` |
| Hostname | Keep the detected computer name | Use the same computer name |

Custom names must contain only lowercase English letters, without spaces, numbers, or hyphens. The names must differ. Hostname identifies the computer; do not enter an email address or profile name.

Click **Save**. Enable recording if the extension asks you to. Browse a regular webpage briefly in each profile, and keep ActivityWatch running.

In official extension version 0.6.0, the source ID combines the Browser name and Hostname. If both profiles use the default `chrome` name on the same computer, they may write to the same source. Different Browser names separate future records. Existing mixed history cannot automatically be separated into profiles; the new sources begin collecting after this setup.

## 2. Connect both sources in the Mac app

1. Open `ActivityWatchWidget.xcodeproj` in Xcode. Use your existing signing team, select **ActivityWatchWidget / My Mac**, and press **Command-R**.
2. Scroll down to **Chrome Web Activity · Second Widget** in the app.
3. Click **Find Sources**.
4. For Chrome 1, select the source containing `aw-watcher-web-chromework_`. For Chrome 2, select the source containing `aw-watcher-web-chromepersonal_`.
5. Optionally name the profiles **Work** and **Personal**, then click **Save & Refresh**.

You can initially connect one profile and leave the other set to **Not Connected**. The profiles cannot share a source. The window, AFK, and browser sources must belong to the same computer.

If a new source is missing, confirm that the extension is enabled, you clicked Save, and you browsed a page in that profile. Check that the extension Hostname matches the computer associated with the app's window source. Do not select the old mixed `aw-watcher-web-chrome_…` source to represent one of the profiles.

## 3. Add and configure the widget

1. Install and launch the complete signed app as described in the main README.
2. Right-click the desktop on your second display and choose **Edit Widgets**.
3. Find **ActivityWatch Widget**, then select **Chrome Web Activity**.
4. After adding it, right-click the widget and select **Edit Widget**. Choose a **Chrome Profile** (Profile 1, Profile 2, or Combined) and a **Display** format (Page Titles or Websites).

To see both profiles side by side, add two Chrome Web Activity widgets and select a different profile for each. The original application usage widget remains available.

## Timing and limitations

- The day starts at midnight in the Mac's current time zone. Only foreground Chrome time counts. **Exclude idle time** also removes AFK periods.
- Both browser extensions can report their respective active tabs simultaneously. The app matches these records against the foreground Chrome window's URL, when available, or its title. It does not simply add both streams together.
- If both profiles show the same page, the records may not identify which profile was in use. That interval remains **Unassigned** and is excluded from individual and combined totals. Combined totals therefore represent the reliably matched portion.
- Title mismatches, missing extension records, internal browser pages, and incognito events are excluded. The app displays unmatched time to help diagnose coverage gaps. Webpage totals may be lower than Chrome's application total.
- Connect both profiles so the app can detect competing background records. With only one connected profile, it cannot rule out the same page being used in another unconnected profile.
- Page Titles groups by website and title, so pages with identical titles on the same website are combined. Websites groups by the full hostname; subdomains remain separate.
- The shared cache includes page titles, website domains, and summary durations. Full URLs, including query parameters, are used temporarily for matching and are not cached. The app does not retrieve page bodies, read Google account identities, or upload records to a cloud service.
- The widget displays today's recorded data. It is not a live mirror of Chrome; WidgetKit controls refresh timing.
- Switching Google accounts within one Chrome profile, using a previously mixed source, or having indistinguishable titles and URLs does not provide enough information to reconstruct profile ownership reliably.
- Profile names you enter and page titles recorded by Chrome retain their original language. The app's built-in interface and this project's documentation are in English.

## Verification and remaining setup

Tests cover simultaneous profile activity, foreground switching, ambiguous pages, idle filtering, duplicate events, midnight boundaries, and compatibility with older settings. Queries were also verified against an isolated ActivityWatch server using synthetic records.

This delivery updates the project files. It does not install or change extensions in your Chrome profiles. Signed registration in Edit Widgets and operation with your actual profiles and displays still require the setup above.

References: [Official extension source IDs](https://github.com/ActivityWatch/aw-watcher-web/blob/v0.6.0/src/background/client.ts), [extension settings fields](https://github.com/ActivityWatch/aw-watcher-web/blob/v0.6.0/src/settings/index.html).
