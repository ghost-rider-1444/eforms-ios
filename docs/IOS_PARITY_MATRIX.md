# iOS parity verification matrix

The iOS target is a native SwiftUI application with a WidgetKit extension. This matrix is the release gate: no signed archive should be described as Android-equivalent until every automated row passes on a macOS runner and every device row has been exercised on an iPhone or iPad.

| Android behaviour | iOS implementation | Automated verification | Device verification |
|---|---|---:|---:|
| University sign-in in a secure embedded browser, including popup SSO | `PortalView` using `WKWebView`, the default protected cookie store and a popup web view | Build/static policy tests | Required: live SSO and MFA |
| Any HTTPS identity-provider address may participate in sign-in | Login-mode navigation permits HTTPS redirects; ordinary portal browsing is restricted to the eForms host | Build | Required |
| Account-bound offline data | SHA-256 account binding in `SessionStore`; mismatch blocks access until local erase | Unit tests | Required |
| Encrypted offline vault | AES-256-GCM with a device-only Keychain key and protected, backup-excluded file | Store transition tests | Required after reinstall/lock |
| Forms, Drafts, Outbox and Sent as separate searchable folders | `MainView` segmented folders and shared search filtering | UI test planned | Required |
| Workspace categories and remembered collapse state | Encrypted `collapsedFormCategories` state | Store/build tests | Required |
| Pin frequently used forms | Encrypted `pinnedForms`; pinned category shown first | Store/build tests | Required |
| Native mobile form controls | `FormView` supports textbox, textarea, number, date, time, combo, radios, checks, signature, section, freetext, calculated and links | Build tests | Required against representative forms |
| Population selection and token autofill | Population snapshots, token substitution and repair of missing/blank token defaults | Build tests | Required against live attendance form |
| Conditional visibility, required conditions and numeric limits | Native condition evaluator and pre-submit validation | Build tests | Required against representative forms |
| Keyboard does not cover lower fields | SwiftUI safe-area/keyboard avoidance and scrollable form | Simulator UI test | Required on small iPhone |
| Clear Signature remains visible | Dedicated full-width action immediately below the PencilKit pad | Simulator UI test | Required |
| Continuous encrypted autosave | Every binding mutation writes the encrypted draft before UI continuation | Store transition tests | Required during forced termination |
| Save Draft locally first and upload online | `saveLocal()` precedes `SyncEngine.saveDraft`; revision check preserves edits made in flight | Store transition tests | Required with connection loss |
| Done submenu: Discard, Save Draft, Submit | Toolbar and bottom menus with destructive confirmation | Build/UI test | Required |
| Offline submission cannot be lost | Complete immutable payload moves atomically from Drafts to local Outbox before sync | Store transition test | Required in airplane mode |
| Background Outbox retry | Network-required `BGProcessingTaskRequest`; foreground/manual retry remains available | Build | Required because iOS scheduling is discretionary |
| Delete all Drafts only, with exact count and confirmation | Draft tombstones retained for server deletion; other collections unchanged | Unit test | Required online and offline |
| Sent and server Outbox downloadable and viewable offline | Encrypted on-demand submission cache and read-only `FormView` | Build | Required with live non-sensitive examples |
| Long read-only text scrolls internally without a scrollbar | Indicator-free nested vertical `ScrollView` | Simulator UI test | Required |
| Attendance banner uses green/amber/red rules | Shared `AttendanceRules`; no purple state | Unit tests | Required with live populations |
| Attendance session list opens the correct population/submission | Route includes population set/id, draft, Outbox or Sent identity | Build | Required |
| Attendance home-screen widget | WidgetKit small/medium widget sharing only start/completion metadata | Timeline unit tests | Required on iPhone and iPad |
| Widget refresh without excessive battery use | Hourly WidgetKit timeline plus system-batched hourly `BGAppRefreshTask`; no continuous process | Build | Required over a normal day |
| App automatic refresh at most hourly | Persisted refresh timestamp shared by foreground/background refresh logic | Build/unit tests | Required |
| Dashboard mobile rendering | Authenticated `WKWebView` with presentation-only responsive CSS | Build | Required against live dashboard |
| Privacy link appears below all Forms | Footer rendered after form categories | UI test | Required |
| Review demo only from Privacy | Local invented data; no API calls | Store test | App Review walkthrough |
| First-use EULA and reacceptance after logout | Versioned EULA acceptance; logout clears acceptance | Unit/build tests | Required |
| Logout wipes this device only | Clears WebKit data, encrypted vault/key, app-group widget status and local settings; no delete API call | Build/store tests | Required |
| Crash reporting without Analytics or form/account metadata | Crashlytics-only Swift package, activated only when an iOS Firebase plist is supplied | Dependency/build test | Verify symbol upload in release project |
| Release has no console logging or Web Inspector | No logging calls; `WKWebView.isInspectable = false`; Release stripping and optimisation enabled | Static scan/build | Inspect release archive |

## Release blockers

1. The GitHub macOS build and test workflow must pass.
2. Live SSO, one non-critical draft and one non-critical submission must be exercised manually without placing credentials in CI.
3. Offline editing, force-quit recovery, Outbox retry, logout wiping and the attendance widget must be checked on a physical device.
4. A unique App Store bundle identifier, Apple Developer team, App Group and matching Firebase iOS configuration must be assigned before signing.
5. App Store Connect validation must accept the final archive.

