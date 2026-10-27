# Build and verification record — version 1.1

Verified on **October 26, 2026 (America/Los_Angeles)**.

## Environment

- macOS 27.2, build 26B123, Apple silicon host.
- Xcode 27.1, build 27A9275, explicitly selected through `DEVELOPER_DIR` for these commands.
- Deployment target: macOS 14.0. Source uses Swift 5 language mode.
- Installed ActivityWatch Rust server reported `aw-server 0.14.1`.

## Completed checks

| Check | Result |
| --- | --- |
| Host + embedded widget, Debug, code signing disabled | **BUILD SUCCEEDED** |
| Host + embedded widget, Release, code signing disabled | **BUILD SUCCEEDED** |
| Release architecture inspection | Host and extension both contain **arm64 and x86_64** |
| Embedded extension inspection | Present under host `Contents/PlugIns/ActivityWatchWidgetExtension.appex` |
| Xcode project, both Info.plists, both entitlements | `plutil -lint`: all OK |
| Build script syntax | `bash -n`: passed |
| Foundation core / transport / store tests | Passed |
| Real ActivityWatch REST integration | Passed on separate loopback port 5679 and synthetic fixture database |
| Final test suite | **15 tests, 0 failures, 0 skipped** |
| Small, medium, large layout previews | Rendered offscreen with SwiftUI and visually inspected |

The real-server fixture verifies query syntax, window/AFK intersection, app aggregation, an event crossing midnight, and an event crossing the query end time. Active time was **150 seconds**; foreground time was **210 seconds**. The actual production ActivityWatch database was not opened or changed. The fixture server was stopped after verification.

Core tests additionally exercise hostname matching, ambiguous/missing buckets, mismatched AFK sources, quoted bucket identifiers, decoding unknown fields, invalid durations, fractional timestamps, the 25-hour autumn DST day, time-zone cache invalidation, old response rejection, settings revision changes, and recovery from a damaged snapshot file.

Test products were placed in a fresh temporary folder after macOS’s file-provider metadata caused a test-bundle signing error under Documents. The documented build/test commands avoid cloud-synced build output locations. Xcode also logged unrelated simulator-service diagnostics; this is a native Mac project and both Mac builds completed successfully.

## Chrome widget verification (version 1.1)

- The extension now has a `WidgetBundle` containing the original application widget and the new AppIntent-configurable **Chrome Web Activity** widget.
- Debug and universal Release compilation passed with both widgets. Profile and grouping parameters were included in the App Intents metadata build.
- Seven new Chrome tests bring the suite to **15 tests, zero failures**, including both real-server integration tests.
- Foreground matching was tested with both profiles reporting simultaneously: only the matching page receives time. Duplicate browser events do not multiply time; non-Chrome foreground windows do not count.
- Same-page overlap across profiles is classified as ambiguous. When the desktop watcher supplies URLs, different URL query parameters can disambiguate identical titles; URLs are not written to the cache.
- The isolated real-server Chrome fixture yielded **30s work + 30s personal**, with **30s ambiguous** excluded from both and combined totals.
- Tests cover AFK filtering, midnight clipping, incognito/internal-page exclusion, distinct source/hostname validation, old settings migration, and independent cache revision/old-response handling.
- Small, medium, and large Chrome views were rendered offscreen and inspected. The preview configuration explicitly selects both profiles and page-title grouping.
- The extension options and bucket naming instructions were checked against the official `aw-watcher-web` **v0.6.0** source. No extension was installed or changed in the user's Chrome profiles.

## Limits of this verification

The initial-delivery signing-identity check returned no valid Apple code-signing identity. This revision also uses unsigned compilation; no signed installation was attempted. Both app builds therefore used `CODE_SIGNING_ALLOWED=NO`; they verify compilation, linking, architecture, packaging, and embedding, **not an installable signed product**.

The following still require a signed installation and were **not verified here**:

- App Group access between the real sandboxed app and extension.
- Registration and appearance in macOS **Edit Widgets**.
- Adding the widget to a physical second monitor.
- Actual WidgetKit refresh scheduling, live system rendering, and deep-link activation.
- Login-item registration/approval and behavior after a real login or sleep/wake cycle.
- End-to-end integration with the user’s real watcher records, including two actual Chrome profiles and their installed extensions.
- Runtime Edit Widget parameter selection in the signed desktop widget.
- Runtime behavior on macOS 14 or Intel hardware (these targets were compiled, not run).

The PNGs in `Previews/` use **synthetic sample data** and SwiftUI offscreen rendering. They are layout previews, not screenshots of a registered desktop widget. No pre-signed app or installer is included.

## Finish installation

Follow the README: select the same real signing team for both targets, build, install the full app bundle into Applications, launch it once, save the ActivityWatch connection, then add **ActivityWatch Today** through **Edit Widgets**. Check that the displayed total matches the host app and that closing the host window leaves its menu-bar updater available. Refresh timing remains controlled by macOS.

## English interface revision — October 27, 2026

All generated Chinese interface strings were translated in the Chrome widget and host dashboard. The setup guide was translated and renamed to `CHROME-SETUP.md`; references were updated. All three Chrome preview images were regenerated with English labels and visually inspected. A source/documentation scan found no remaining Chinese characters in the delivered project.

This revision changes display text and documentation only. The prior 15-test functional verification applies to unchanged data-processing logic; the tests were not rerun for the translations. Debug and Release builds were checked with signing disabled. Actual webpage titles and user-entered profile names retain their original language. Signed runtime registration remains unverified.
