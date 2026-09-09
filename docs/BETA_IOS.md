# iOS beta — build preparation, not a completed release

Status on 2026-09-08: no `.ipa` was produced. The available host is Windows;
`flutter build ipa` exits with `Could not find a subcommand named "ipa"`.
No connected macOS build host or Apple signing team is available in this session.
Native compilation, plugin compatibility and installation remain unverified.

The existing Flutter iOS project is preserved. Runner now uses the proposed
beta Bundle ID `id.modellyng.beta`, with matching RunnerTests identifiers, and
the display name `Modellyng Beta`. The ID still needs to be registered or made
available to the operator's Apple team. No Apple team or certificate is invented.
The existing iOS 13 deployment target must be checked against native dependencies
when Xcode resolves them. The app icon catalog still contains the template assets
and must be replaced before a public release.

## Continue on a Mac

1. Install Xcode and its iOS platform tools, accept its license, and use Flutter
   3.44.9 (the version used for the Android beta). Run `flutter doctor -v`.
2. Transfer the current frontend source and lockfile, including uncommitted
   changes. A clone of the old committed revision is not this beta. Exclude
   generated builds, `.dart_tool`, Android signing files and backend secrets.
3. Transfer only `.tool-state/beta/client.json` as the client build configuration,
   keeping the same relative path. It contains the public HTTPS addresses and
   anonymous client key. Never use `backend/.env` as Dart defines.
4. From `frontend/`, run `flutter pub get`, then open `ios/Runner.xcodeproj` in
   Xcode. Select Runner > Signing & Capabilities, choose the real Apple team and
   enable automatic signing. Confirm the Bundle ID is available to that team.
5. Run `flutter analyze` and `flutter test`, then build with the numeric iOS
   version below. Do not reuse Android's `0.1.0-beta.1` as the iOS version string.

```sh
cd frontend
flutter build ipa --release --build-name=0.1.0 --build-number=1 \
  --dart-define-from-file=../.tool-state/beta/client.json
```

Successful signing/export produces `frontend/build/ios/ipa/*.ipa`. An unsigned
archive is not an installable public beta. Export may require a distribution
provisioning profile and a paid Apple Developer Program membership. Public
TestFlight distribution is a separate step and has not been performed.

For personal-device development with a free Apple account, connect the iPhone,
select the Personal Team in Xcode, and use `flutter run` with the same Dart define
file. Personal provisioning expires and requires reinstalling; it does not give
unrestricted public distribution. Do not send signing credentials in chat.

Before sharing an iOS build, test login/session refresh, private PDF upload,
analysis, evidence PDF viewing, export save/cancel, background/resume and logout
on an actual iPhone. The beta still depends on the computer-hosted services in
`BETA_ANDROID.md`; the HTTPS tunnel must remain active and its embedded hostname
must match the current session. Rotate the development Gemini key before wider
distribution, as already recorded in PROJECT_STATUS.

References: [Flutter iOS release](https://docs.flutter.dev/deployment/ios),
[Apple account and Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account).
