# Installation Guide

This guide explains how to build and install the Android companion app from
source, prepare its local engine, and use the phone as a private-LAN installer
server for a PS5. The project also has a hosted builder, described below.

The Android app is published as source, not as a ready-to-install APK. The
original Android engine archive is distributed as an asset on the
[v1.0.1 GitHub Release](https://github.com/senvmg-byte/snipers-youtube-builder/releases/tag/android-engine-v1.0.1).
It is not stored in the Git branch. This exact archive is 127,298,522 bytes
with SHA-256
`ef2668f2616c19a2837e2cb95aee08907ad77b55ab247355263a9872ed7bb6f9`.
The published manifest is the source of truth for the archive integrity check.
The archive is distributed unchanged; its internal `ENGINE-NOTICES.txt`
contains a pre-existing version-text discrepancy (it says 1.0.0 while the
manifest and release identify 1.0.1).

## 1. Check compatibility and prepare safely

Supported firmware profiles are 11.00, 11.20, 11.60, 12.00, 12.02, 12.20,
12.40, 12.60, 12.70, 13.00, 13.20, 13.40, 13.42, and 13.60. Firmware 11.40
is not supported.

For console installation, have an existing jailbreak and etaHEN available
where required by the installer. The phone and PS5 must be able to reach each
other on a trusted private Wi-Fi network. Do not expose the phone's server
through router port forwarding or a public tunnel.

Startup payloads and YouTube modifications can crash the console or cause data
loss. Use only on a console you own or are authorized to administer. Keep a
verified backup, review every selected ELF, and do not power off during an
installation. A successful image build is not proof of compatibility with
your firmware or payload combination.

## 2. Install Android build tools on Windows

The steps below use Windows PowerShell. Install:

1. **Git for Windows**.
2. **Flutter stable** with Dart 3.5 or newer. Add `C:\src\flutter\bin` (or your
   Flutter installation's `bin` directory) to `PATH`.
3. **Android Studio**. In SDK Manager, install Android SDK Platform, Android
   SDK Build-Tools, and Android NDK; accept the Android SDK licenses.
4. **JDK 17** and **Node.js 24** for the host-side ELF patch step. Node.js
   24.18.0 is the version pinned for the Android engine.
5. **Android Platform Tools** (`adb`), either from Android Studio's SDK
   Manager or a standalone Platform Tools installation.

Open a new PowerShell window and verify the tools:

```powershell
flutter --version
flutter doctor -v
java -version
node --version
adb version
```

Resolve Flutter's Android toolchain or SDK-license errors reported by
`flutter doctor` before building.

## 3. Download the source and exact engine archive

Clone the published source branch:

```powershell
git clone --branch android-app-installation-guide --single-branch `
  https://github.com/senvmg-byte/snipers-youtube-builder.git
Set-Location .\snipers-youtube-builder
```

Download `snipers-android-engine-v1.0.1.tar.gz` from the
[engine release](https://github.com/senvmg-byte/snipers-youtube-builder/releases/tag/android-engine-v1.0.1)
and save it as:

```text
flutter_app\assets\engine\snipers-android-engine-v1.0.1.tar.gz
```

Verify that the file is complete and unmodified before using it:

```powershell
$archive = ".\flutter_app\assets\engine\snipers-android-engine-v1.0.1.tar.gz"
$manifest = Get-Content ".\flutter_app\assets\engine\manifest.json" -Raw |
    ConvertFrom-Json
$file = Get-Item $archive
$hash = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()

if ($file.Length -ne $manifest.bytes -or $hash -ne $manifest.sha256) {
    throw "Engine archive size or SHA-256 does not match manifest.json."
}
```

Keep `manifest.json` from the same source branch. Do not edit its expected
size or digest to bypass a failed check.

## 4. Prepare the Android native runtime libraries

The engine archive contains the pinned Android ARM64 Node.js, .NET, Zig, and
supporting libraries. Gradle also needs their ARM64 `.so` files in the
repository's generated native-library directory. Extract the archive and
prepare that directory from PowerShell:

```powershell
$archive = (Resolve-Path `
  ".\flutter_app\assets\engine\snipers-android-engine-v1.0.1.tar.gz").Path
$extract = Join-Path $env:TEMP ("snipers-engine-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory $extract | Out-Null
tar -xzf $archive -C $extract
if ($LASTEXITCODE -ne 0) { throw "Could not extract engine archive." }

$engine = Join-Path $extract "snipers-engine"
$native = Join-Path (Get-Location) `
  "relapse-host\build\android-engine\native-libs\arm64-v8a"
New-Item -ItemType Directory -Path $native -Force | Out-Null

Copy-Item (Join-Path $engine "node\bin\node") (Join-Path $native "libnode.so")
Copy-Item (Join-Path $engine "dotnet\dotnet") (Join-Path $native "libdotnet.so")
Copy-Item (Join-Path $engine "toolchains\zig\zig") (Join-Path $native "libzig.so")
Get-ChildItem (Join-Path $engine "node\lib") -File |
  Copy-Item -Destination $native
```

Create and patch the Android library-name aliases required by the bundled
Node.js runtime:

```powershell
$aliases = @(
  @{ Source = "libz.so.1";             Alias = "libz.so" },
  @{ Source = "libcrypto.so.3";       Alias = "libcrypto.so" },
  @{ Source = "libssl.so.3";          Alias = "libssl.so" },
  @{ Source = "libicui18n.so.78";     Alias = "libicui18n.so" },
  @{ Source = "libicuuc.so.78";       Alias = "libicuuc.so" },
  @{ Source = "libicudata.so.78";     Alias = "libicudata.so" },
  @{ Source = "libsqlite3.so.3.54.0"; Alias = "libsqlite3.so" }
)
$patcher = ".\relapse-host\builder\patch-android-elf.mjs"
foreach ($item in $aliases) {
    $versioned = Join-Path $native $item.Source
    if (-not (Test-Path $versioned)) {
        throw "Missing engine runtime library: $($item.Source)"
    }
    $alias = Join-Path $native $item.Alias
    Copy-Item $versioned $alias -Force
    node $patcher $alias
    if ($LASTEXITCODE -ne 0) { throw "Failed to patch $($item.Alias)." }
}
node $patcher (Join-Path $native "libnode.so")
if ($LASTEXITCODE -ne 0) { throw "Failed to patch libnode.so." }
```

The patcher only updates the ELF library names needed for Android loading; it
does not replace or rebuild the pinned toolchain binaries. Keep the extracted
engine until the APK build is complete.

## 5. Build the ARM64 APK

Fetch Dart dependencies and build a debug APK for testing:

```powershell
Push-Location .\flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
Pop-Location
```

The debug APK is:

```text
flutter_app\build\app\outputs\flutter-apk\app-debug.apk
```

For personal release builds, the project requires a signing key. Configure
`snipersReleaseStoreFile`, `snipersReleaseStorePassword`,
`snipersReleaseKeyAlias`, and `snipersReleaseKeyPassword` in your
user-level Gradle properties, then run:

```powershell
Push-Location .\flutter_app
flutter build apk --release --target-platform android-arm64
Pop-Location
```

Keep the keystore and passwords private. Use the same signing key for future
updates; losing it prevents Android from updating that signed app.

## 6. Install and initialize the app on Android

1. On the phone, enable **Developer options** and **USB debugging**.
2. Connect it by USB, approve the computer's debugging prompt, and confirm it
   is visible:

   ```powershell
   adb devices
   ```

   The device should show as `device`, not `unauthorized`.
3. Install or update the debug APK:

   ```powershell
   adb install -r `
     .\flutter_app\build\app\outputs\flutter-apk\app-debug.apk
   ```

   Alternatively, copy the APK to the phone and open it there. If Android
   requests permission, allow installation from that file manager.
4. Open **Snipers Builder**. On the local-build screen, press **Cài engine từ
   APK** (Install engine from APK). Wait for checksum validation, extraction,
   and the ready status before beginning a build.
5. Allow the requested file access when importing ELF payloads. Keep only the
   payloads you intend to run; use payload files from sources you trust.

Engine preparation needs several hundred megabytes of free app storage. Keep
additional free storage for the APK and generated image.

## 7. Build a local image and install it over Wi-Fi

1. Connect the phone and PS5 to the same trusted Wi-Fi network. Disable
   client/AP isolation if enabled; it prevents devices on Wi-Fi from reaching
   one another.
2. Keep etaHEN active as required by the installer. In the Android app,
   select the exact supported PS5 firmware, add the intended ELF payloads,
   and start the local build. Wait for the build result and do not close the
   app.
3. Start the Android **LAN server** from the app. Keep the app in the
   foreground and prevent Android battery settings from suspending it.
4. On the PS5, open the confirmation-code URL shown by the app. Use the
   current phone URL; if the phone reconnects to Wi-Fi or receives a new IP,
   rebuild the image and use the newly displayed URL.
5. Read the installer status and confirm the replacement only when prompted.
   The installer verifies the image and saves a verified backup before
   replacing the YouTube startup. Keep both devices on and connected until
   the PS5 reports success.
6. Reopen YouTube only after installation has completed and the app reports
   the result. If the app offers cleanup, it removes temporary build files;
   it retains the installed engine and PS5 backup.

If YouTube is missing, the phone proxies the pinned package over LAN,
including HTTP byte-range requests. The PS5 does not need direct Internet
access for that package transfer, but the phone must be able to access the
configured package source.

For a failed install, first check that the app is still running, the phone
and PS5 remain on the same subnet, and the displayed phone address is current.
Then inspect the PS5 console/debug log and the app's result for the first
error. Do not repeatedly retry a package registration that the console reports
as rejected.

## 8. Use the hosted builder instead

The Android app also opens the online builder. To build directly on the PS5:

1. Open the [Snipers builder](https://sniperscheats.lol/builder/) in the PS5
   browser.
2. Select the exact firmware and choose hosted payloads or supply ELF files.
3. Review the selection, start the build, and keep the browser open while the
   bundle is prepared and downloaded.
4. Follow the installer prompts. Confirm replacement only after checking the
   target and backup status.

Online build codes and generated build files expire after a limited time; use
the displayed code promptly.

## Troubleshooting checklist

- **Archive size/hash error:** download the asset again from the
  [v1.0.1 release](https://github.com/senvmg-byte/snipers-youtube-builder/releases/tag/android-engine-v1.0.1)
  and rerun the manifest check in step 3.
- **Gradle cannot find native libraries:** confirm every file in
  `relapse-host\build\android-engine\native-libs\arm64-v8a` exists and repeat
  the copy/alias steps in step 4.
- **Android installation reports insufficient space:** free app-private
  storage and run **Cài engine từ APK** again.
- **PS5 cannot open the installer URL:** verify the LAN server is running,
  use the current URL, and check that Wi-Fi client isolation is disabled.
- **Checksum/package error:** keep the app open, check the first PS5 log
  error, and do not proceed if the installer reports a hash mismatch.

## Credits and licenses

The integration includes work from upstream project and payload authors.
Preserve their attribution and license terms; see [CREDITS.md](CREDITS.md),
[LICENSES.md](LICENSES.md), and the notices in the engine archive. The engine
release includes the upstream Node.js 24.18.0 and PS5 Payload SDK 0.43 license
texts as separate assets.
