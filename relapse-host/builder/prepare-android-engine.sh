#!/data/data/com.termux/files/usr/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
: "${PREFIX:?Run this script from Termux}"
: "${HOME:?HOME is required}"

ENGINE_VERSION=1.0.1
KERNEL_COMMIT=dd8e4e0914c5e9d066ee1f9b056be76cb992c8e0
SDK_SHA256=a9cc9929f21b2b2c5d5b309f3bab4997067c45281c0622cf4838b1aecba66fcb
ZIG_SHA256=f7a654acc967864f7a050ddacfaa778c7504a0eca8d2b678839c21eea47c992b
DOTNET_VERSION=9.0.20
NODE_VERSION=v24.18.0
SDK=${PS5_PAYLOAD_SDK:-"$HOME/toolchains/ps5-payload-sdk"}
SDK_ARCHIVE="$HOME/ps5-payload-sdk-v0.43.zip"
ZIG_ARCHIVE="$HOME/zig-aarch64-linux-0.14.1.tar.xz"
OUT="$ROOT/build/android-engine"
STAGE="$OUT/package"
ENGINE="$STAGE/snipers-engine"
ARCHIVE="$OUT/snipers-android-engine-v$ENGINE_VERSION.tar.gz"
NATIVE_LIBS="$OUT/native-libs/arm64-v8a"
APK_ENGINE_ASSETS="$ROOT/flutter_app/assets/engine"

case "$STAGE" in
  "$ROOT"/build/android-engine/package) ;;
  *) echo "Refusing unexpected package staging path: $STAGE" >&2; exit 1 ;;
esac

test "$(node --version)" = "$NODE_VERSION" || {
  echo "Expected Node $NODE_VERSION" >&2
  exit 1
}
test "$("$PREFIX/lib/dotnet/dotnet" --version)" = 9.0.121 || {
  echo "Expected .NET SDK 9.0.121 for package preparation" >&2
  exit 1
}
test "$("$PREFIX/lib/dotnet/dotnet" --list-runtimes | grep -F "Microsoft.NETCore.App $DOTNET_VERSION")" ||
  { echo "Expected .NET runtime $DOTNET_VERSION" >&2; exit 1; }
test "$(sha256sum "$SDK_ARCHIVE" | cut -d' ' -f1)" = "$SDK_SHA256" || {
  echo "PS5 Payload SDK archive does not match the pinned v0.43 input" >&2
  exit 1
}
test "$(sha256sum "$ZIG_ARCHIVE" | cut -d' ' -f1)" = "$ZIG_SHA256" || {
  echo "Zig archive does not match the pinned 0.14.1 input" >&2
  exit 1
}

kernel_head=$(git -C "$ROOT/relapse-y2jb/third_party/Relapse-Exploit" rev-parse HEAD)
test "$kernel_head" = "$KERNEL_COMMIT" || {
  echo "Relapse kernel checkout does not match the pinned source" >&2
  exit 1
}

rm -rf "$STAGE"
rm -rf "$OUT/obj"
mkdir -p "$ENGINE/node/bin" "$ENGINE/node/lib" "$ENGINE/dotnet/host/fxr/$DOTNET_VERSION" \
  "$ENGINE/dotnet/shared/Microsoft.NETCore.App/$DOTNET_VERSION" \
  "$ENGINE/toolchains" "$ENGINE/relapse-host/vendor" \
  "$ENGINE/relapse-host/artifacts/youtube-installer" \
  "$ENGINE/relapse-y2jb/tools/ufs2/publish" "$OUT/dotnet-home" "$OUT/nuget-packages" \
  "$NATIVE_LIBS" "$APK_ENGINE_ASSETS"

cp "$PREFIX/bin/node" "$ENGINE/node/bin/node"
for library in \
  libz.so.1 \
  libcares.so \
  libsqlite3.so.3.54.0 \
  libcrypto.so.3 \
  libssl.so.3 \
  libicui18n.so.78 \
  libicuuc.so.78 \
  libicudata.so.78 \
  libc++_shared.so
do
  test -e "$PREFIX/lib/$library" || {
    echo "Missing Node runtime library: $library" >&2
    exit 1
  }
  cp -L "$PREFIX/lib/$library" "$ENGINE/node/lib/$library"
done
LD_LIBRARY_PATH="$ENGINE/node/lib" "$ENGINE/node/bin/node" --version

cp "$PREFIX/lib/dotnet/dotnet" "$ENGINE/dotnet/dotnet"
cp "$PREFIX/lib/dotnet/host/fxr/$DOTNET_VERSION/libhostfxr.so" \
  "$ENGINE/dotnet/host/fxr/$DOTNET_VERSION/"
cp -R "$PREFIX/lib/dotnet/shared/Microsoft.NETCore.App/$DOTNET_VERSION/." \
  "$ENGINE/dotnet/shared/Microsoft.NETCore.App/$DOTNET_VERSION/"

tar -xJf "$ZIG_ARCHIVE" -C "$ENGINE/toolchains"
mv "$ENGINE/toolchains/zig-aarch64-linux-0.14.1" "$ENGINE/toolchains/zig"
"$ENGINE/toolchains/zig/zig" version
cp -R "$SDK" "$ENGINE/ps5-payload-sdk"

mkdir -p "$ENGINE/relapse-host" "$ENGINE/relapse-y2jb"
cp -R "$ROOT/relapse-host/builder" "$ENGINE/relapse-host/"
cp -R "$ROOT/relapse-host/vendor/ftpsrv-0.21.1" "$ENGINE/relapse-host/vendor/"
mkdir -p "$ENGINE/relapse-host/site/online" "$ENGINE/relapse-host/site/src"
cp -R "$ROOT/relapse-host/site/online/2ea9344fcd6fbcb7" \
  "$ENGINE/relapse-host/site/online/"
cp "$ROOT/relapse-host/site/src/autoload.js" "$ROOT/relapse-host/site/src/sha256.js" \
  "$ENGINE/relapse-host/site/src/"
cp -R "$ROOT/relapse-host/artifacts/youtube-installer/13.60" \
  "$ENGINE/relapse-host/artifacts/youtube-installer/"
cp -R "$ROOT/relapse-y2jb/tools" "$ENGINE/relapse-y2jb/"
cp -R "$ROOT/relapse-y2jb/src" "$ENGINE/relapse-y2jb/"
mkdir -p "$ENGINE/relapse-y2jb/third_party"
cp -R "$ROOT/relapse-y2jb/third_party/y2jb-host" "$ENGINE/relapse-y2jb/third_party/"
cp -R "$ROOT/relapse-y2jb/third_party/Relapse-Exploit" \
  "$ENGINE/relapse-y2jb/third_party/"
rm -rf "$ENGINE/relapse-y2jb/third_party/Relapse-Exploit/.git"
cp "$ROOT/relapse-y2jb/LICENSE" "$ROOT/relapse-y2jb/SNIPERS-CREDITS.md" \
  "$ROOT/relapse-y2jb/SNIPERS-SETUP.md" "$ENGINE/relapse-y2jb/"
mkdir -p "$ENGINE/experimental"
cp "$ROOT/experimental/channel.mjs" "$ROOT/experimental/firmware-profiles.json" \
  "$ROOT/experimental/release-manifest.json" "$ROOT/experimental/hosted-payloads.json" \
  "$ENGINE/experimental/"
mkdir -p "$ENGINE/etahen-13.60/Source Code/extern/tiny-json"
cp "$ROOT/etahen-13.60/Source Code/extern/tiny-json/tiny-json.cpp" \
  "$ENGINE/etahen-13.60/Source Code/extern/tiny-json/tiny-json.hpp" \
  "$ENGINE/etahen-13.60/Source Code/extern/tiny-json/LICENSE" \
  "$ENGINE/etahen-13.60/Source Code/extern/tiny-json/"

cat > "$ENGINE/android-engine-source-lock.json" <<EOF
{"schemaVersion":1,"kernelCommit":"$KERNEL_COMMIT"}
EOF
FIRMWARE_JSON=$(node -e "const p=require('$ROOT/experimental/firmware-profiles.json');process.stdout.write(JSON.stringify(p.firmwares.map(x=>x.firmware)))")
SOURCE_TAG=$(node -e "const p=require('$ROOT/experimental/release-manifest.json');process.stdout.write(p.releaseTagPrefix)")
cat > "$ENGINE/engine.json" <<EOF
{"schemaVersion":1,"version":"$ENGINE_VERSION","sourceTag":"$SOURCE_TAG","firmware":$FIRMWARE_JSON,"kernelCommit":"$KERNEL_COMMIT"}
EOF

export DOTNET_ROOT="$PREFIX/lib/dotnet"
export DOTNET_CLI_HOME="$OUT/dotnet-home"
export NUGET_PACKAGES="$OUT/nuget-packages"
export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1
"$PREFIX/lib/dotnet/dotnet" restore "$ROOT/relapse-y2jb/tools/ufs2/ImageBuilder.csproj" \
  --configfile "$ROOT/relapse-y2jb/tools/ufs2/NuGet.Config"
"$PREFIX/lib/dotnet/dotnet" publish "$ROOT/relapse-y2jb/tools/ufs2/ImageBuilder.csproj" \
  --no-restore --configuration Release --output "$ENGINE/relapse-y2jb/tools/ufs2/publish"

cp "$ROOT/LICENSES.md" "$ROOT/CREDITS.md" "$ENGINE/"
mkdir -p "$ENGINE/licenses/node" "$ENGINE/licenses/dotnet" "$ENGINE/licenses/zig"
for license in "$PREFIX/share/doc/nodejs/LICENSE" "$PREFIX/share/doc/nodejs/NOTICE"; do
  if test -f "$license"; then cp "$license" "$ENGINE/licenses/node/"; fi
done
for license in "$PREFIX/lib/dotnet/LICENSE.txt" "$PREFIX/lib/dotnet/ThirdPartyNotices.txt"; do
  if test -f "$license"; then cp "$license" "$ENGINE/licenses/dotnet/"; fi
done
for license in "$ENGINE/toolchains/zig/LICENSE" "$ENGINE/toolchains/zig/README.md"; do
  if test -f "$license"; then cp "$license" "$ENGINE/licenses/zig/"; fi
done

cat > "$ENGINE/ENGINE-NOTICES.txt" <<EOF
Snipers Android local engine $ENGINE_VERSION

Engine build tools:
- Node.js $NODE_VERSION, obtained from Termux package nodejs-lts; see licenses/node.
- Zig 0.14.1, upstream archive SHA-256 $ZIG_SHA256; see licenses/zig.
- .NET runtime $DOTNET_VERSION, provisioned from Termux; see licenses/dotnet.
- PS5 Payload SDK 0.43, upstream archive SHA-256 $SDK_SHA256.
- Relapse/Y2JB sources retain their upstream notices; see CREDITS.md and LICENSES.md.

The package includes source and compiler/runtime inputs only. User-selected ELF
payloads and console packages are not included. The generated installer
downloads and verifies the local build over LAN after PS5 confirmation, saves
a backup of the previous YouTube startup, and installs the selected startup.
EOF

mkdir -p "$(dirname "$ROOT/flutter_app/assets/engine/manifest.json")"
rm -f "$ARCHIVE"
tar -czf "$ARCHIVE" -C "$STAGE" snipers-engine
archive_hash=$(sha256sum "$ARCHIVE" | cut -d' ' -f1)
archive_bytes=$(wc -c < "$ARCHIVE" | tr -d ' ')
uncompressed_bytes=$(du -sb "$ENGINE" | cut -f1)
cat > "$ROOT/flutter_app/assets/engine/manifest.json" <<EOF
{"version":"$ENGINE_VERSION","sourceTag":"$SOURCE_TAG","archive":"snipers-android-engine-v$ENGINE_VERSION.tar.gz","sha256":"$archive_hash","bytes":$archive_bytes,"uncompressedBytes":$uncompressed_bytes,"firmware":$FIRMWARE_JSON}
EOF
cp "$ARCHIVE" "$APK_ENGINE_ASSETS/snipers-android-engine-v$ENGINE_VERSION.tar.gz"

cp "$ENGINE/node/bin/node" "$NATIVE_LIBS/libnode.so"
cp "$ENGINE/dotnet/dotnet" "$NATIVE_LIBS/libdotnet.so"
cp "$ENGINE/toolchains/zig/zig" "$NATIVE_LIBS/libzig.so"
cp -R "$ENGINE/node/lib/." "$NATIVE_LIBS/"
cp "$ENGINE/node/lib/libsqlite3.so.3.54.0" "$NATIVE_LIBS/libsqlite3.so"
for library in libz.so.1 libcrypto.so.3 libssl.so.3 libicui18n.so.78 libicuuc.so.78 libicudata.so.78 libsqlite3.so.3.54.0; do
  alias="${library%%.so.*}.so"
  cp "$NATIVE_LIBS/$library" "$NATIVE_LIBS/$alias"
  node "$ENGINE/relapse-host/builder/patch-android-elf.mjs" "$NATIVE_LIBS/$alias"
done
node "$ENGINE/relapse-host/builder/patch-android-elf.mjs" "$NATIVE_LIBS/libnode.so"

echo "Engine archive: $ARCHIVE"
echo "Archive bytes: $archive_bytes"
echo "Uncompressed bytes: $uncompressed_bytes"
echo "Archive SHA-256: $archive_hash"
