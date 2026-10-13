# Installation Guide

This guide covers the hosted PS5 builder and the Android companion app. The
Android application is published as source; no prebuilt APK or proprietary
toolchain archive is included in this source repository.

## Requirements and safety

- A PS5 on one of the supported firmware profiles: 11.00, 11.20, 11.60,
  12.00, 12.02, 12.20, 12.40, 12.60, 12.70, 13.00, 13.20, 13.40, 13.42, or
  13.60. Firmware 11.40 is not supported.
- An existing jailbreak and etaHEN where required by the installer.
- For the Android LAN workflow, an Android ARM64 phone and a trusted private
  Wi-Fi network shared with the PS5.

Use this project only on a console you own or are authorized to administer.
Payloads and startup modifications can crash the console or cause data loss.
Hardware behavior can vary by firmware and payload; a successful build is not
proof of compatibility. Keep a verified backup and do not interrupt an
installation. Never expose the Android LAN server through router port
forwarding or a public tunnel.

## Use the hosted builder

1. On the PS5, open the [Snipers builder](https://sniperscheats.lol/builder/)
   in the browser.
2. Select the matching firmware and either choose hosted payloads or supply
   your own ELF files.
3. Review the selected payloads, build the bundle, and follow the page's
   installer instructions. Do not close the page while the build or download
   is in progress.
4. Confirm installation only after reviewing the installer prompt. The
   installer verifies the image and backs up the existing YouTube startup
   before replacing it.

The supported flow requires the jailbreak and etaHEN state described by the
builder. See [build and self-hosting notes](BUILDING.md) for service setup.

## Build and install the Android app

### Build the APK from source

Install Flutter with Dart 3.5 or newer, Android Studio and its Android SDK,
Android NDK, and JDK 17. The local engine is generated from pinned external
inputs and is intentionally not committed because it contains large
third-party toolchain/runtime files.

1. Clone this repository and provision the matching inputs described in
   [Android build notes](flutter_app/README.md) and
   [build requirements](BUILDING.md). Preserve all upstream license notices.
2. From a Termux/Linux environment with the required inputs, build the
   installer template and prepare the Android engine:

   ```sh
   node relapse-host/builder/build-youtube-installer.mjs
   sh relapse-host/builder/prepare-android-engine.sh
   ```

   This generates the Android engine archive, metadata, and native runtime
   libraries. Keep the generated manifest and archive from the same run.
3. From `flutter_app`, fetch Flutter dependencies and build:

   ```sh
   flutter pub get
   flutter build apk --release --target-platform android-arm64
   ```

   For local testing, use `flutter run` or
   `flutter build apk --debug`. The APK is under
   `flutter_app/build/app/outputs/flutter-apk/`.
4. Transfer the APK to the Android phone, install it, and open the app.
   Release builds require a private signing key; keep the key and its
   passwords private and use the same key for subsequent app updates.

Source can be browsed and built without the generated engine archive, but
building a functional standalone local-engine APK requires the external
inputs and preparation step above. Do not upload generated archives, SDKs,
private signing keys, or console data.

### Build a bundle on Android and install over LAN

1. Connect the phone and PS5 to the same trusted private Wi-Fi network. Keep
   the phone awake and the app open during the build and installation.
2. In the app, install the verified engine bundled into your prepared APK
   using **Cài engine từ APK**. Select a supported firmware and the ELF
   payloads you intend to use, then build the startup image.
3. Start the app's LAN server and use the confirmation-code URL shown by the
   app on the PS5 browser. If the phone's Wi-Fi address changes, rebuild the
   image so its embedded address is current.
4. Follow the PS5 installer prompts. The installer checks the image and
   YouTube package and asks before replacing the existing startup. Keep the
   phone, PS5, and browser connected until the installer reports completion.
5. If installation fails, keep the console open to its installer result and
   check its console/debug log for the first error. Verify the phone and PS5
   are still on the same LAN and that the phone has not suspended the app.

When YouTube needs to be provisioned, the Android server proxies the pinned
package over LAN, including HTTP byte-range requests. This avoids requiring
direct Internet access from the PS5, but the phone itself still needs the
network access required by the configured package source. The LAN server is
unauthenticated apart from the build code; stop it when finished and do not
make it reachable from untrusted networks.

## Credits and licenses

This project integrates upstream projects and payloads. Their authors retain
their original credit and license terms; see [CREDITS.md](CREDITS.md),
[LICENSES.md](LICENSES.md), and the component notices before redistributing
modified source or binaries.
