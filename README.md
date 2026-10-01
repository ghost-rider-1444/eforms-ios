# eForms for iPhone and iPad

This directory contains the native iOS/iPadOS port of the Android eForms app and its Attendance WidgetKit extension. The app is independently developed and is not affiliated with or endorsed by the University of Manchester.

## Generate and test on macOS

The project is defined with XcodeGen so that the checked-in source remains reviewable and deterministic:

```sh
brew install xcodegen
cd ios
xcodegen generate
xcodebuild test \
  -project eForms.xcodeproj \
  -scheme eForms \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO
```

The repository workflow at `.github/workflows/ios-simulator.yml` performs the same build and tests on a public GitHub macOS runner and uploads an unsigned simulator `.app`. It never stores or uses a Manchester username, password or session.

## Deployment configuration

Before creating a TestFlight/App Store archive:

1. Change `app.offlineform.companion.ios` in `project.yml` to the publisher's registered unique bundle identifier.
2. Change the App Group in both entitlement files and `WidgetSnapshot.swift` to a group registered to the same Apple Developer team.
3. Set `DEVELOPMENT_TEAM` in `project.yml` or in Xcode Signing & Capabilities for both targets.
4. Register both bundle identifiers and the App Group in the Apple Developer portal.
5. Create a Firebase iOS app for the final bundle identifier and add its `GoogleService-Info.plist` to `ios/eForms`. It is ignored by Git and Crashlytics remains inactive without it.
6. Generate the project, select **Any iOS Device**, run Product > Archive, then validate and upload through Xcode Organizer.

The app uses only Firebase Crashlytics. Google Analytics is not linked. The privacy manifest declares no developer data collection and documents the required UserDefaults API reason.

## Security model

- Form data is encrypted with AES-256-GCM.
- The key is stored as device-only Keychain material and the vault uses iOS file protection.
- The vault is excluded from consumer backup.
- Sign-in occurs only in a WebKit browser; the app never receives the password.
- Normal portal browsing is restricted to the eForms HTTPS host. Login may follow HTTPS identity-provider redirects.
- The attendance widget receives only encrypted start times and completion booleans through the private App Group, never session titles, form answers, signatures or usernames.
- Logout removes the local vault, Keychain key, website data, local legal acceptance and widget state without calling a server deletion endpoint.

See `docs/IOS_PARITY_MATRIX.md` for the verification gate that must be completed before a deployment build is labelled feature-equivalent.
