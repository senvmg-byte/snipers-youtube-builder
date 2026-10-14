**[Unified release and source](https://github.com/GronedWaffel/snipers-youtube-builder/releases/tag/v2.0.0)**

# Snipers YouTube Builder — PS5 11.00–13.60

Create a YouTube startup bundle for 14 exact PS5 firmware targets from 11.00 through 13.60. **11.40 and firmware below 11.00 are excluded.** Choose hosted payloads or your own ELF files directly on PS5, or optionally from a phone/computer.

[Open the builder](https://sniperscheats.lol/builder/) | [Payload downloads](https://sniperscheats.lol/payloads/) | [Build and validation details](experimental/README.md) | [Credits](CREDITS.md)

The experimental line is merged into main. New bundles include the exact user-tested etaHEN Unified r1 ELF, with PS4/PS5 FPS display, plugins, Toolbox placement and the controller startup fix. Existing YouTube installations do not update themselves: rebuild and install a new bundle. Firmware-specific feature testing remains scoped; see the etaHEN release notes.

The native handoff owns the payloads before closing YouTube, retains the five-second dashboard wait, and waits for etaHEN/kstuff readiness before subsequent payloads. Installation needs an existing jailbreak and etaHEN. The installer chooses the matching YouTube package, verifies it and the startup image, and can reconcile a lost DPI reply against actual installation completion.

Source layout: `relapse-host` contains the builder, installer and payload supervisors; `relapse-y2jb` contains Y2JB/Relapse integration and UFS2 tools; `etahen-13.60` retains its historical directory name but contains the unified source. `experimental` holds exact profiles, pinned research, build scripts, local integration results and deployment examples.

The original 13.60 ten-run test is historical and does not establish compatibility of this experimental release. See [stable history](release/STABLE-HISTORY.md). Existing component credits and licenses remain in [CREDITS.md](CREDITS.md) and [LICENSES.md](LICENSES.md). Snipers' integration builds on the original exploit, etaHEN, payload and toolchain authors' work.

An ARM64 Android companion app built with Flutter is available in [flutter_app/](flutter_app/). It includes the hosted builder and a standalone local PS5 payload/image workflow. The full step-by-step Android guide is included below; see also the [expanded installation guide](INSTALLATION.md) and [Android implementation/build notes](flutter_app/README.md).

## Android companion app

The Android app provides two ways to use the builder:

- **Hosted builder:** opens `https://sniperscheats.lol/builder/` in an embedded browser, supports the site's file selection, and opens installer downloads externally when needed.
- **Local builder:** prepares the pinned Android engine in the app's private storage, accepts user-selected payload files, creates a firmware-specific startup image locally, and serves the installer to the PS5 over the phone's private Wi-Fi network. After the engine is installed, building the image does not require Termux or Internet access.

### Android app features

- **Firmware profiles:** 11.00, 11.20, 11.60, 12.00, 12.02, 12.20, 12.40, 12.60, 12.70, 13.00, 13.20, 13.40, 13.42, and 13.60. Firmware 11.40 is unsupported.
- **Payload selection and ordering:** imports up to eight ELF/BIN payloads, with a 64 MiB per-file and 128 MiB combined limit. It validates x86-64 ELF structure and records SHA-256; payloads run in the displayed order, which can be changed or removed before building. A valid ELF file is not proof that it is safe or compatible.
- **Integrity and progress:** verifies the engine archive size and SHA-256 against the bundled manifest, reports engine/build errors and progress, and displays image and installer SHA-256 digests after a build.
- **LAN installer server:** binds to private IPv4 Wi-Fi addresses on port `8787`. The PS5 uses a confirmation-code URL and downloads the installer/image from the phone. The server provides firmware-matched offset tables, the browser runtime modules and ROP worker, and the local installer assets.
- **YouTube package proxy:** when the console needs the pinned YouTube package, the phone relays it from the configured HTTPS source, including `HEAD`, HTTP byte-range requests and range response metadata. This can avoid direct PS5 Internet access; the phone still needs access to the package source.
- **Confirmed installation and cleanup:** the PS5 installer checks image integrity and creates a verified backup before replacing YouTube startup, after explicit confirmation. The app can remove temporary image/installer/build data, while retaining the installed engine and imported payloads. The PS5 backup is retained.
- **Upstream source check:** checks GitHub for a newer source release and verifies its published SHA-256 before updating supported firmware/release catalogs. This does not update the Android app code or native runtime; a newer APK is required for app code changes.
- **Android UI:** Snipers branding with an adaptive high-refresh request where supported. Android thermal, battery, and display policy can choose a lower refresh rate.

The LAN server is unauthenticated apart from the temporary build confirmation code. Keep it on a trusted private network, leave the app open while the PS5 is using it, and never expose it with router port-forwarding or a public tunnel.

### Step-by-step Android installation

#### 1. Check requirements

- Android ARM64 phone, Windows 10/11 build computer, Git, Flutter/Dart 3.5 or newer, Android Studio/SDK/NDK, JDK 17, Node.js 24, and Android Platform Tools (`adb`).
- PS5 on one of the supported firmware profiles above, with an existing jailbreak and etaHEN where required by the installer.
- For local installation, the phone and PS5 must be able to communicate over the same trusted private Wi-Fi network.

The engine release includes pinned Node.js v24.18.0, .NET runtime 9.0.20, Zig 0.14.1, and PS5 Payload SDK 0.43 for the local Android ARM64 runtime. It is distributed as an asset rather than committed into Git. Its archive remains byte-for-byte unchanged; the existing `ENGINE-NOTICES.txt` says 1.0.0 although its manifest and release are version 1.0.1.

#### 2. Clone the source and download the engine

In PowerShell:

```powershell
git clone --branch android-app-installation-guide --single-branch `
  https://github.com/senvmg-byte/snipers-youtube-builder.git
Set-Location .\snipers-youtube-builder
```

Download `snipers-android-engine-v1.0.1.tar.gz` from the [Android engine release](https://github.com/senvmg-byte/snipers-youtube-builder/releases/tag/android-engine-v1.0.1) into `flutter_app\assets\engine\`. The expected SHA-256 is `ef2668f2616c19a2837e2cb95aee08907ad77b55ab247355263a9872ed7bb6f9`; verify both digest and size against `manifest.json`:

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

Do not change the expected hash or size to bypass a mismatch.

#### 3. Extract the native Android runtime libraries

The archive has the Android ARM64 Node.js, .NET and Zig executables and support libraries. Gradle also needs copies under `relapse-host\build\android-engine\native-libs\arm64-v8a`. Run:

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

Create the linker aliases and update their ELF dependency names using the project's patcher:

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

This process changes only the required Android ELF library names, not the pinned toolchain versions.

#### 4. Build the APK

```powershell
Push-Location .\flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-arm64
Pop-Location
```

The debug APK is `flutter_app\build\app\outputs\flutter-apk\app-debug.apk`. A signed release APK requires your own private signing key; see [Android build notes](flutter_app/README.md). Never share the keystore or signing passwords.

#### 5. Install the APK and prepare its engine

Enable USB debugging on the phone, connect it to the PC, approve the debugging prompt, then run:

```powershell
adb devices
adb install -r .\flutter_app\build\app\outputs\flutter-apk\app-debug.apk
```

Open **Snipers Builder** on the phone, enter the local workspace, and tap **Cài engine từ APK**. Wait for checksum verification, extraction and the ready state. Allow the file picker to access the ELF/BIN files you choose. The engine preparation needs several hundred megabytes of free app storage.

#### 6. Build and install a PS5 image over LAN

1. Connect the PS5 and phone to the same private Wi-Fi. Disable client isolation if devices cannot reach each other.
2. Keep etaHEN active as required. In the app, choose the exact firmware, select up to eight payloads, arrange their execution order, then tap **Build image local** and wait for its image/installer hashes.
3. Start the app's LAN server. Keep the app open and prevent Android battery management from suspending it.
4. On the PS5, open the confirmation-code URL displayed by the phone. If the phone's Wi-Fi IP changes, rebuild and use the new URL.
5. Review the PS5 installer status. Confirm only when the target and verified backup are correct. Keep both devices connected until the installer reports completion.
6. If the app offers cleanup, it removes temporary build files; the engine, imported payloads and PS5 backup are retained.

If YouTube is missing, the phone can proxy the pinned package over LAN (including byte ranges); the phone still needs access to the configured package source. Check the first console/debug error for failures. Do not retry if package registration is explicitly rejected.

#### 7. Use the online builder instead

On the PS5, open [sniperscheats.lol/builder](https://sniperscheats.lol/builder/), select the exact firmware and payloads, review the selection, and follow its download/installer prompts. Keep the browser open while the build is prepared.

## Safety and compatibility

Use only on a console you own or are authorized to administer. Payloads may crash the console. Retain a verified backup and never interrupt replacement. A valid ELF, successful local build, or working LAN server does not guarantee firmware compatibility or successful execution. Use the LAN server only on a trusted private network.

## Credits and licenses

This project integrates upstream software; its authors retain their copyright and license terms. Preserve [CREDITS.md](CREDITS.md), [LICENSES.md](LICENSES.md), and component notices. The engine is optional; source builds without it are possible, but the standalone local-builder APK requires the external engine archive and Android native libraries.
