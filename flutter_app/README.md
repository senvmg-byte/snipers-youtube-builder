# Snipers YouTube Builder for Android (Flutter)

The app supports three workflows:

- **Snipers branding** uses a custom lime-on-charcoal reticle/play logo in the
  app interface and Android launcher icon.
- **High-refresh UI** requests a 120 Hz Android display mode where supported;
  the system may still select a lower rate based on device settings, thermal
  state, or battery policy. Local build progress events are rate-limited so
  compiler output does not continuously invalidate the interface.
- **Online builder** embeds `https://sniperscheats.lol/builder/`, supports file
  selection on the site, and opens installer downloads in the Android browser.
- **LAN server** binds only to private IPv4 Wi-Fi addresses on port `8787`.
  Once a local build is complete, open its confirmation-code URL on the PS5.
  The server also serves the offset table matching the build firmware, as
  required by the PS5 browser installer, both `/builder/runtime/` and
  `/builder/ex/runtime/` JavaScript module paths, and the root-relative ROP
  worker requested by the PS5 browser. If YouTube is missing, the installer
  asks etaHEN to download its pinned package from this phone over LAN; the
  phone securely proxies the package source, including byte-range requests, so
  the PS5 does not need direct Internet access. Engine preparation validates
  the browser runtime files and its firmware offset tables.
  The PS5 installer downloads and verifies the image over LAN, then replaces
  YouTube startup only after explicit confirmation and a verified backup. The
  app removes that build's temporary Android workspace after the PS5 reports
  success; the installed startup and PS5 backup are retained. The server is
  unauthenticated apart from the build code; do not expose it through router
  port forwarding or a public tunnel.
- **Manual build cleanup** is available from the local build result. It removes
  that build's image, installer, and intermediate workspace after confirmation,
  while retaining the installed engine and imported payload files.
- **Standalone local builder** installs the engine embedded in the APK after
  checking its archive size and SHA-256, imports user-selected ELF files, and
  builds without Termux or a network connection.
- The local builder supports the 14 firmware profiles published by source
  release v2.0.0: 11.00, 11.20, 11.60, 12.00, 12.02, 12.20, 12.40, 12.60,
  12.70, 13.00, 13.20, 13.40, 13.42, and 13.60. Firmware 11.40 remains
  unsupported because the upstream source has no matching Relapse table.
- **GitHub source updates** check the upstream latest release. When a newer
  source ZIP is available, the app verifies the SHA-256 digest published by
  GitHub before updating the engine's firmware and release catalogs. The
  verified source ZIP is retained in app-private storage. This updates source
  data, not the Android APK or native runtimes; code changes to the Android
  application still require installing a newer APK. After a source update,
  local builds remain offline.

## Preparing the local engine

The single ARM64 APK includes the Android Node.js, .NET, and Zig executables in
Android's installed native-library directory, plus the hash-pinned engine
archive containing their runtime, PS5 Payload SDK, UFS2 builder, and pinned
project sources. The app verifies that archive's size and SHA-256 before
installing it into its private files directory. It does not include a Debian
root filesystem, PRoot, or user payloads.

In the Termux checkout with the pinned toolchain inputs available, first build
the installer template described in the root [build notes](../BUILDING.md),
then prepare the Android engine:

```text
node relapse-host/builder/build-youtube-installer.mjs
sh relapse-host/builder/prepare-android-engine.sh
```

This writes the compressed engine archive and native runtime libraries under
`relapse-host/build/android-engine/`, and copies the archive plus matching
metadata into `flutter_app/assets/engine/`. Build the single APK after
preparing these files. In the app, tap **Cài engine từ APK**; installation
rejects archive size/hash mismatches and checks the unpacked engine metadata.
After installation, Termux and Internet access are not needed for local builds.

Keep the manifest and archive from the same packaging run. Do not publish the
PS5 Payload SDK or the complete engine package without first checking the
upstream distribution terms.

## Local-build limits

Local builds accept the firmware profiles listed above and generate a
firmware-specific installer template when one is not bundled. Generated images use the LAN installer flow. Installing explicitly replaces
the existing YouTube startup after hashing it and saving a backup on the PS5.
A successful build is not proof that an image or payload works on PS5 hardware.
No hardware validation has been completed. Only use the LAN server on a trusted
private network, and treat generated payloads and images as untrusted until
independently verified.

## Build an APK

Install Flutter, Android Studio, the Android SDK, and JDK 17. From this
directory run:

```text
flutter pub get
flutter run
```

To create a debug APK:

```text
flutter build apk --debug
```

Release APKs must be signed with the same private release key on every update.
The Android Gradle configuration reads signing values from user-level Gradle
properties (`snipersReleaseStoreFile`, `snipersReleaseStorePassword`,
`snipersReleaseKeyAlias`, and `snipersReleaseKeyPassword`) and fails a release
build if any are missing. Keep the keystore and those credentials backed up
securely; losing the key prevents upgrades of an installed release.

For the signed ARM64 release APK:

```text
flutter build apk --release --target-platform android-arm64
```

The debug APK is written to `build/app/outputs/flutter-apk/app-debug.apk`.
The release APK is written to `build/app/outputs/flutter-apk/app-release.apk`.
