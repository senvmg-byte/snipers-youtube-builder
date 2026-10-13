package com.gronedwaffel.snipers_youtube_builder

import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.SystemClock
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Locale
import java.util.concurrent.Executors
import java.io.RandomAccessFile
import java.util.zip.ZipFile

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private var eventSink: EventChannel.EventSink? = null
    private var pendingPickerResult: MethodChannel.Result? = null
    @Volatile
    private var buildProcess: Process? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        window.attributes = window.attributes.apply {
            preferredRefreshRate = 120f
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(::handleMethodCall)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "engineStatus" -> {
                val arguments = call.arguments as? Map<*, *>
                val version = arguments?.get("version") as? String
                val sha256 = arguments?.get("sha256") as? String
                if (version == null || sha256 == null) {
                    result.error("INVALID_ARGUMENT", "Engine version and hash are required.", null)
                } else {
                    result.success(engineIsInstalled(version, sha256))
                }
            }

            "prepareEngine" -> {
                val manifest = call.arguments as? Map<*, *>
                if (manifest == null) {
                    result.error("INVALID_ARGUMENT", "An engine manifest is required.", null)
                } else {
                    ioExecutor.execute { prepareEngine(manifest, result) }
                }
            }
            "supportedFirmwares" -> {
                try {
                    result.success(readSupportedFirmwares(File(filesDir, "engine")))
                } catch (error: Exception) {
                    completeError(result, "FIRMWARE_CATALOG_INVALID", error.message ?: "Could not read firmware catalog.")
                }
            }
            "readInstallerAsset" -> {
                val asset = call.arguments as? String
                if (asset == null) {
                    result.error("INVALID_ARGUMENT", "An installer page asset path is required.", null)
                } else {
                    ioExecutor.execute { readInstallerAsset(asset, result) }
                }
            }
            "checkUpstreamSource" -> {
                val arguments = call.arguments as? Map<*, *>
                val bundledTag = arguments?.get("bundledTag") as? String
                if (bundledTag == null || !SOURCE_TAG_PATTERN.matches(bundledTag)) {
                    result.error("INVALID_ARGUMENT", "A valid bundled source tag is required.", null)
                } else {
                    ioExecutor.execute { checkUpstreamSource(bundledTag, result) }
                }
            }
            "updateUpstreamSource" -> {
                val arguments = call.arguments as? Map<*, *>
                val bundledTag = arguments?.get("bundledTag") as? String
                val tag = arguments?.get("tag") as? String
                if (bundledTag == null || !SOURCE_TAG_PATTERN.matches(bundledTag) ||
                    tag == null || !SOURCE_TAG_PATTERN.matches(tag)) {
                    result.error("INVALID_ARGUMENT", "Valid source release tags are required.", null)
                } else {
                    ioExecutor.execute { updateUpstreamSource(bundledTag, tag, result) }
                }
            }
            "pickPayloads" -> beginPicker(result)
            "runBuild" -> runBuild(call.arguments, result)
            else -> result.notImplemented()
        }
    }

    private fun beginPicker(result: MethodChannel.Result) {
        if (pendingPickerResult != null) {
            result.error("PICKER_BUSY", "Another file picker is already open.", null)
            return
        }

        pendingPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        try {
            startActivityForResult(intent, PICKER_REQUEST)
        } catch (error: Exception) {
            pendingPickerResult = null
            result.error("PICKER_FAILED", error.message ?: "Could not open the file picker.", null)
        }
    }

    @Deprecated("Deprecated in Android, retained for FlutterActivity result routing.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICKER_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        val result = pendingPickerResult
        pendingPickerResult = null

        if (result == null) return
        if (resultCode != RESULT_OK || data == null) {
            result.success(null)
            return
        }

        ioExecutor.execute { importPayloads(data, result) }
    }

    private fun prepareEngine(manifest: Map<*, *>, result: MethodChannel.Result) {
        val version = manifest["version"] as? String
        val archiveName = manifest["archive"] as? String
        val expectedHash = manifest["sha256"] as? String
        val expectedBytes = (manifest["bytes"] as? Number)?.toLong()
        val unpackedBytes = (manifest["uncompressedBytes"] as? Number)?.toLong()
        val firmware = manifest["firmware"] as? List<*>
        if (version == null || !ENGINE_VERSION_PATTERN.matches(version) ||
            archiveName != "snipers-android-engine-v$version.tar.gz" || expectedHash == null ||
            !SHA256_PATTERN.matches(expectedHash) || expectedBytes == null ||
            expectedBytes <= 0 || expectedBytes > MAX_ENGINE_ARCHIVE_BYTES ||
            unpackedBytes == null || unpackedBytes <= 0 ||
            unpackedBytes > MAX_ENGINE_UNPACKED_BYTES || firmware == null ||
            firmware.isEmpty() || firmware.any { it !is String || !FIRMWARE_PATTERN.matches(it) } ||
            firmware.toSet().size != firmware.size) {
            completeError(result, "INVALID_MANIFEST", "The bundled engine manifest is invalid.")
            return
        }

        val requiredSpace = expectedBytes + unpackedBytes * 2
        if (StatFs(filesDir.path).availableBytes < requiredSpace) {
            completeError(
                result,
                "INSUFFICIENT_SPACE",
                "Free at least ${formatBytes(requiredSpace)} before preparing the engine.",
            )
            return
        }

        val archive = File(cacheDir, "snipers-engine-package.part")
        val staging = File(filesDir, "engine-staging")
        val active = File(filesDir, "engine")
        val previous = File(filesDir, "engine-previous")

        try {
            archive.delete()
            assets.open("flutter_assets/assets/engine/$archiveName").use { input ->
                copyAndVerify(input, archive, expectedBytes, expectedHash)
            }
            emitProgress("SHA-256 khớp; đang giải nén engine vào vùng riêng của ứng dụng.")
            deleteRecursively(staging)
            if (!staging.mkdirs()) throw IOException("Could not create the engine staging directory.")

            val tar = ProcessBuilder(
                "/system/bin/toybox",
                "tar",
                "-xzf",
                archive.absolutePath,
                "-C",
                staging.absolutePath,
                "--strip-components",
                "1",
            ).redirectErrorStream(true).start()
            val tarOutput = tar.inputStream.bufferedReader().use { it.readText() }
            val tarExit = tar.waitFor()
            if (tarExit != 0) {
                throw IOException("Engine archive extraction failed ($tarExit): ${tarOutput.takeLast(2000)}")
            }

            validateEngineTree(staging, version, firmware.filterIsInstance<String>())
            makeEngineFilesReadOnly(staging)
            emitProgress("Engine đã giải nén và kiểm tra xong.")

            deleteRecursively(previous)
            if (active.exists() && !active.renameTo(previous)) {
                throw IOException("Could not move the previous engine aside.")
            }
            if (!staging.renameTo(active)) {
                if (previous.exists()) previous.renameTo(active)
                throw IOException("Could not activate the prepared engine.")
            }

            val stateTemp = File(filesDir, "engine-state.part")
            stateTemp.writeText(
                JSONObject()
                    .put("version", version)
                    .put("sha256", expectedHash)
                    .toString(),
            )
            val state = File(filesDir, ENGINE_STATE_FILE)
            if (state.exists() && !state.delete()) {
                throw IOException("Could not replace the engine state record.")
            }
            if (!stateTemp.renameTo(state)) {
                throw IOException("Could not save the engine state record.")
            }
            deleteRecursively(previous)
            mainHandler.post { result.success(mapOf("version" to version, "sha256" to expectedHash)) }
        } catch (error: Exception) {
            Log.e(TAG, "Engine preparation failed.", error)
            deleteRecursively(staging)
            completeError(result, "ENGINE_PREPARATION_FAILED", error.message ?: "Could not prepare the engine.")
        } finally {
            archive.delete()
        }
    }

    private fun checkUpstreamSource(bundledTag: String, result: MethodChannel.Result) {
        try {
            val release = fetchLatestSourceRelease()
            val currentTag = installedSourceTag(bundledTag)
            mainHandler.post {
                result.success(sourceReleaseMap(release, currentTag))
            }
        } catch (error: Exception) {
            completeError(result, "SOURCE_CHECK_FAILED", error.message ?: "Could not check GitHub releases.")
        }
    }

    private fun updateUpstreamSource(
        bundledTag: String,
        expectedTag: String,
        result: MethodChannel.Result,
    ) {
        val temporaryArchive = File(cacheDir, "upstream-source.part")
        try {
            val release = fetchLatestSourceRelease()
            val currentTag = installedSourceTag(bundledTag)
            if (release.tag != expectedTag || compareSourceTags(release.tag, currentTag) <= 0) {
                throw IOException("The requested GitHub source release is no longer newer than the installed source.")
            }
            val requiredSpace = release.bytes + 8L * 1024 * 1024
            if (StatFs(filesDir.path).availableBytes < requiredSpace) {
                throw IOException("Free at least ${formatBytes(requiredSpace)} before updating source metadata.")
            }

            temporaryArchive.delete()
            val connection = (URL(release.url).openConnection() as HttpURLConnection).apply {
                connectTimeout = NETWORK_CONNECT_TIMEOUT_MS
                readTimeout = NETWORK_READ_TIMEOUT_MS
                instanceFollowRedirects = true
                setRequestProperty("User-Agent", "Snipers-YouTube-Builder-Android")
                setRequestProperty("Accept", "application/octet-stream")
            }
            try {
                if (connection.responseCode !in 200..299) {
                    throw IOException("GitHub source download failed (${connection.responseCode}).")
                }
                connection.inputStream.use { input ->
                    copyAndVerify(input, temporaryArchive, release.bytes, release.sha256)
                }
            } finally {
                connection.disconnect()
            }
            emitProgress("SHA-256 source ZIP khớp; đang kiểm tra catalog firmware.")

            val engine = File(filesDir, "engine")
            val sourceFiles = readSourceCatalogs(temporaryArchive, release.tag, engine)
            installSourceCatalogs(engine, sourceFiles)

            val sourceDirectory = File(filesDir, "upstream-sources")
            if (!sourceDirectory.exists() && !sourceDirectory.mkdirs()) {
                throw IOException("Could not create the verified source archive directory.")
            }
            val retainedArchive = File(sourceDirectory, "${release.tag}-source.zip")
            if (retainedArchive.exists() && !retainedArchive.delete()) {
                throw IOException("Could not replace the previous verified source archive.")
            }
            if (!temporaryArchive.renameTo(retainedArchive)) {
                throw IOException("Could not retain the verified GitHub source archive.")
            }
            val current = installedSourceTag(bundledTag)
            emitProgress("Source ${release.tag} đã xác minh và cập nhật catalog firmware.")
            mainHandler.post { result.success(sourceReleaseMap(release, current)) }
        } catch (error: Exception) {
            Log.e(TAG, "GitHub source update failed.", error)
            completeError(result, "SOURCE_UPDATE_FAILED", error.message ?: "Could not update GitHub source metadata.")
        } finally {
            temporaryArchive.delete()
        }
    }

    private data class SourceRelease(
        val tag: String,
        val name: String,
        val bytes: Long,
        val sha256: String,
        val url: String,
    )

    private fun fetchLatestSourceRelease(): SourceRelease {
        val connection = (URL(GITHUB_LATEST_RELEASE_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = NETWORK_CONNECT_TIMEOUT_MS
            readTimeout = NETWORK_READ_TIMEOUT_MS
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "Snipers-YouTube-Builder-Android")
            setRequestProperty("Accept", "application/vnd.github+json")
        }
        try {
            if (connection.responseCode !in 200..299) {
                throw IOException("GitHub release lookup failed (${connection.responseCode}).")
            }
            val release = JSONObject(connection.inputStream.use { readUtf8Bounded(it, MAX_RELEASE_JSON_BYTES) })
            val tag = release.optString("tag_name")
            if (!SOURCE_TAG_PATTERN.matches(tag) ||
                release.optBoolean("draft") ||
                release.optBoolean("prerelease")) {
                throw IOException("GitHub latest release metadata is invalid.")
            }
            val expectedAssetName = "Snipers-YouTube-Builder-${tag.removePrefix("v")}-source.zip"
            val assets = release.optJSONArray("assets")
                ?: throw IOException("GitHub release has no source assets.")
            val asset = (0 until assets.length())
                .mapNotNull { assets.optJSONObject(it) }
                .firstOrNull { it.optString("name") == expectedAssetName }
                ?: throw IOException("GitHub release is missing $expectedAssetName.")
            val digest = asset.optString("digest")
            val hash = digest.removePrefix("sha256:")
            val size = asset.optLong("size", -1)
            val downloadUrl = asset.optString("browser_download_url")
            val expectedUrl =
                "https://github.com/GronedWaffel/snipers-youtube-builder/releases/download/$tag/$expectedAssetName"
            if (!SHA256_PATTERN.matches(hash) || size <= 0 ||
                size > MAX_SOURCE_ARCHIVE_BYTES || downloadUrl != expectedUrl) {
                throw IOException("GitHub source asset metadata is invalid or exceeds the size limit.")
            }
            return SourceRelease(tag, release.optString("name", tag), size, hash, downloadUrl)
        } finally {
            connection.disconnect()
        }
    }

    private fun sourceReleaseMap(release: SourceRelease, currentTag: String): Map<String, Any> =
        mapOf(
            "currentTag" to currentTag,
            "latestTag" to release.tag,
            "name" to release.name,
            "sourceBytes" to release.bytes,
            "sourceSha256" to release.sha256,
            "updateAvailable" to (compareSourceTags(release.tag, currentTag) > 0),
        )

    private fun installedSourceTag(bundledTag: String): String {
        val releaseFile = File(filesDir, "engine/experimental/release-manifest.json")
        if (!releaseFile.isFile) return bundledTag
        val tag = JSONObject(releaseFile.readText()).optString("releaseTagPrefix")
        if (!SOURCE_TAG_PATTERN.matches(tag)) {
            throw IOException("The installed source release tag is invalid.")
        }
        return tag
    }

    private fun compareSourceTags(left: String, right: String): Int {
        val leftParts = left.removePrefix("v").split('.').map { it.toInt() }
        val rightParts = right.removePrefix("v").split('.').map { it.toInt() }
        for (index in 0..2) {
            val compared = leftParts[index].compareTo(rightParts[index])
            if (compared != 0) return compared
        }
        return 0
    }

    private fun readSourceCatalogs(
        archive: File,
        expectedTag: String,
        engine: File,
    ): Pair<ByteArray, ByteArray> {
        ZipFile(archive).use { zip ->
            fun readEntry(name: String): ByteArray {
                val entry = zip.getEntry(name) ?: throw IOException("Source ZIP is missing $name.")
                if (entry.isDirectory || entry.size <= 0 || entry.size > MAX_SOURCE_CATALOG_BYTES) {
                    throw IOException("Source catalog $name has an invalid size.")
                }
                return zip.getInputStream(entry).use { readBytesBounded(it, MAX_SOURCE_CATALOG_BYTES) }
            }

            val profileBytes = readEntry("experimental/firmware-profiles.json")
            val releaseBytes = readEntry("experimental/release-manifest.json")
            val profiles = JSONObject(String(profileBytes, Charsets.UTF_8))
            val firmwareProfiles = profiles.optJSONArray("firmwares")
                ?: throw IOException("Source firmware catalog has no profile list.")
            if (firmwareProfiles.length() !in 1..MAX_FIRMWARE_PROFILES) {
                throw IOException("Source firmware catalog has an invalid profile count.")
            }
            val seen = mutableSetOf<String>()
            for (index in 0 until firmwareProfiles.length()) {
                val profile = firmwareProfiles.optJSONObject(index)
                    ?: throw IOException("Source firmware profile $index is invalid.")
                val firmware = profile.optString("firmware")
                if (!FIRMWARE_PATTERN.matches(firmware) || !seen.add(firmware)) {
                    throw IOException("Source firmware catalog has an invalid or duplicate version.")
                }
                if (!File(engine, "relapse-y2jb/third_party/Relapse-Exploit/offsets/$firmware.js").isFile) {
                    throw IOException(
                        "Source adds firmware $firmware, but the installed Android engine has no matching kernel table. Install a compatible APK/source bundle first.",
                    )
                }
            }

            val release = JSONObject(String(releaseBytes, Charsets.UTF_8))
            if (release.optString("channel") != "unified" ||
                release.optString("basePath") != "/builder" ||
                release.optString("releaseTagPrefix") != expectedTag) {
                throw IOException("Source release manifest does not match the GitHub release tag.")
            }
            return profileBytes to releaseBytes
        }
    }

    private fun installSourceCatalogs(engine: File, catalogs: Pair<ByteArray, ByteArray>) {
        val experimental = File(engine, "experimental")
        if (!experimental.isDirectory) throw IOException("The installed engine source directory is missing.")
        val profileFile = File(experimental, "firmware-profiles.json")
        val releaseFile = File(experimental, "release-manifest.json")
        val profilePart = File(experimental, "firmware-profiles.json.part")
        val releasePart = File(experimental, "release-manifest.json.part")
        val profileBackup = File(experimental, "firmware-profiles.json.previous")
        val releaseBackup = File(experimental, "release-manifest.json.previous")
        profilePart.writeBytes(catalogs.first)
        releasePart.writeBytes(catalogs.second)
        profileBackup.delete()
        releaseBackup.delete()
        if (!profileFile.setWritable(true, true) || !releaseFile.setWritable(true, true)) {
            throw IOException("Could not prepare the source catalog for a verified update.")
        }
        if (!profileFile.renameTo(profileBackup) || !releaseFile.renameTo(releaseBackup)) {
            profileBackup.renameTo(profileFile)
            releaseBackup.renameTo(releaseFile)
            throw IOException("Could not stage the previous source catalog.")
        }
        try {
            if (!profilePart.renameTo(profileFile) || !releasePart.renameTo(releaseFile)) {
                throw IOException("Could not activate the verified source catalog.")
            }
            if (!profileFile.setReadable(true, false) || !profileFile.setWritable(false, false) ||
                !releaseFile.setReadable(true, false) || !releaseFile.setWritable(false, false)) {
                throw IOException("Could not protect the updated source catalog.")
            }
            val installed = readSupportedFirmwares(engine)
            val profileJson = JSONObject(profileFile.readText()).getJSONArray("firmwares")
            val expected = (0 until profileJson.length()).map { profileJson.getJSONObject(it).getString("firmware") }
            if (installed != expected) throw IOException("The updated source catalog did not validate.")
            profileBackup.delete()
            releaseBackup.delete()
        } catch (error: Exception) {
            profileFile.delete()
            releaseFile.delete()
            profileBackup.renameTo(profileFile)
            releaseBackup.renameTo(releaseFile)
            profilePart.delete()
            releasePart.delete()
            throw error
        }
    }

    private fun readUtf8Bounded(input: InputStream, limit: Int): String =
        String(readBytesBounded(input, limit), Charsets.UTF_8)

    private fun readBytesBounded(input: InputStream, limit: Int): ByteArray {
        val output = java.io.ByteArrayOutputStream()
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        var total = 0
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            if (total > limit) throw IOException("Downloaded GitHub metadata exceeds its size limit.")
            output.write(buffer, 0, count)
        }
        return output.toByteArray()
    }

    private fun copyAndVerify(
        source: InputStream,
        destination: File,
        expectedBytes: Long,
        expectedHash: String,
    ) {
        val digest = MessageDigest.getInstance("SHA-256")
        var copied = 0L
        FileOutputStream(destination).use { output ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = source.read(buffer)
                if (count < 0) break
                copied += count
                if (copied > expectedBytes) {
                    throw IOException("The bundled engine is larger than its pinned size.")
                }
                digest.update(buffer, 0, count)
                output.write(buffer, 0, count)
            }
            output.fd.sync()
        }
        if (copied != expectedBytes) {
            throw IOException("Bundled engine size mismatch: expected $expectedBytes bytes, received $copied.")
        }
        val actualHash = digest.digest().joinToString("") { "%02x".format(it) }
        if (!actualHash.equals(expectedHash, ignoreCase = true)) {
            throw SecurityException("Bundled engine SHA-256 mismatch. The archive was not installed.")
        }
    }

    private fun validateEngineTree(root: File, expectedVersion: String, expectedFirmware: List<String>) {
        val metadata = JSONObject(File(root, "engine.json").readText())
        if (metadata.optInt("schemaVersion") != 1 ||
            metadata.optString("version") != expectedVersion ||
            metadata.optJSONArray("firmware").toStringList() != expectedFirmware) {
            throw IOException("The extracted engine metadata does not match the pinned manifest.")
        }
        val profiles = readSupportedFirmwares(root)
        if (profiles != expectedFirmware) {
            throw IOException("The engine firmware catalog does not match the pinned manifest.")
        }

        val required = listOf(
            "node/lib/libicudata.so.78",
            "dotnet/shared/Microsoft.NETCore.App/9.0.20/System.Private.CoreLib.dll",
            "ps5-payload-sdk/target/lib/crt1.o",
            "experimental/channel.mjs",
            "experimental/firmware-profiles.json",
            "experimental/release-manifest.json",
            "experimental/hosted-payloads.json",
            "relapse-host/builder/web/install.html",
            "relapse-host/builder/web/install.js",
            "relapse-host/site/src/autoload.js",
            "relapse-host/site/src/sha256.js",
            "relapse-host/site/online/2ea9344fcd6fbcb7/runtime.js",
            "relapse-host/site/online/2ea9344fcd6fbcb7/src/firmware.js",
            "relapse-host/site/online/2ea9344fcd6fbcb7/src/utils/syscalls.js",
            "relapse-host/site/online/2ea9344fcd6fbcb7/src/rop.js",
            "relapse-host/site/online/2ea9344fcd6fbcb7/src/main.js",
            "relapse-host/site/online/2ea9344fcd6fbcb7/src/webkit.js",
            "relapse-host/site/online/2ea9344fcd6fbcb7/src/utils/mem.js",
            "relapse-host/site/online/2ea9344fcd6fbcb7/src/utils/int64.js",
            "relapse-host/site/online/2ea9344fcd6fbcb7/src/utils/rop_slave.js",
            "etahen-13.60/Source Code/extern/tiny-json/tiny-json.cpp",
            "relapse-host/builder/android-local-build.mjs",
            "relapse-host/artifacts/youtube-installer/13.60/Snipers-YouTube-Installer.template.elf",
            "relapse-y2jb/tools/ufs2/publish/ImageBuilder.dll",
        )
        for (relativePath in required) {
            if (!File(root, relativePath).isFile) {
                throw IOException("The engine archive is missing $relativePath.")
            }
        }
        val browserRuntime = File(root, "relapse-host/site/online/2ea9344fcd6fbcb7")
        for (firmware in profiles) {
            if (!File(browserRuntime, "offsets/$firmware.js").isFile) {
                throw IOException("The browser runtime is missing offsets for $firmware.")
            }
        }
        for (name in NATIVE_EXECUTABLES) {
            val executable = File(applicationInfo.nativeLibraryDir, name)
            if (!executable.isFile || !executable.canExecute()) {
                throw IOException("The APK is missing its executable runtime $name.")
            }
        }
    }

    private fun JSONArray?.containsString(value: String): Boolean {
        if (this == null) return false
        for (index in 0 until length()) {
            if (optString(index) == value) return true
        }
        return false
    }

    private fun JSONArray?.toStringList(): List<String> {
        if (this == null) return emptyList()
        return (0 until length()).map { index ->
            val value = opt(index) as? String
                ?: throw IOException("The engine firmware manifest contains an invalid entry.")
            if (!FIRMWARE_PATTERN.matches(value)) {
                throw IOException("The engine firmware manifest contains an invalid version.")
            }
            value
        }
    }

    private fun readSupportedFirmwares(root: File): List<String> {
        val profiles = JSONObject(File(root, "experimental/firmware-profiles.json").readText())
        val firmwares = profiles.optJSONArray("firmwares")
            ?: throw IOException("The engine firmware profile list is missing.")
        val values = (0 until firmwares.length()).map { index ->
            val profile = firmwares.optJSONObject(index)
                ?: throw IOException("The engine firmware profile is invalid.")
            val firmware = profile.optString("firmware")
            if (!FIRMWARE_PATTERN.matches(firmware)) {
                throw IOException("The engine firmware profile has an invalid version.")
            }
            val offsetTable = File(root, "relapse-y2jb/third_party/Relapse-Exploit/offsets/$firmware.js")
            if (!offsetTable.isFile) {
                throw IOException("The engine is missing the $firmware kernel offset table.")
            }
            firmware
        }
        if (values.isEmpty() || values.distinct().size != values.size) {
            throw IOException("The engine firmware profile list is empty or contains duplicates.")
        }
        return values
    }

    private fun makeEngineFilesReadOnly(directory: File) {
        val children = directory.listFiles()
            ?: throw IOException("Could not read extracted engine directory: ${directory.path}")
        for (child in children) {
            if (child.isDirectory) {
                makeEngineFilesReadOnly(child)
            } else if (child.isFile) {
                if (!child.setReadable(true, false) || !child.setWritable(false, false)) {
                    throw IOException("Could not make an engine file read-only: ${child.path}")
                }
            }
        }
    }

    private fun importPayloads(intent: Intent, result: MethodChannel.Result) {
        val uris = mutableListOf<Uri>()
        val clips = intent.clipData
        if (clips != null) {
            for (index in 0 until clips.itemCount) {
                uris.add(clips.getItemAt(index).uri)
            }
        } else {
            intent.data?.let(uris::add)
        }

        if (uris.isEmpty()) {
            mainHandler.post { result.success(emptyList<Map<String, Any>>()) }
            return
        }
        if (uris.size > MAX_PAYLOADS) {
            completeError(result, "TOO_MANY_PAYLOADS", "Select no more than $MAX_PAYLOADS ELF files.")
            return
        }

        val directory = File(filesDir, "build-inputs")
        if (!directory.exists() && !directory.mkdirs()) {
            completeError(result, "PAYLOAD_IMPORT_FAILED", "Could not create the private payload directory.")
            return
        }
        val imported = mutableListOf<Map<String, Any>>()
        var totalBytes = 0L
        try {
            uris.forEachIndexed { index, uri ->
                val displayName = displayName(uri)
                if (!displayName.endsWith(".elf", ignoreCase = true) &&
                    !displayName.endsWith(".bin", ignoreCase = true)) {
                    throw IOException("Selected file '$displayName' is not an ELF or BIN file.")
                }
                val destination = File(directory, "${System.currentTimeMillis()}-$index.elf")
                val (bytes, sha256) = copyPayload(uri, destination)
                if (bytes < MIN_PAYLOAD_BYTES || bytes > MAX_PAYLOAD_BYTES) {
                    destination.delete()
                    throw IOException("Payload '$displayName' must be between 64 bytes and 64 MiB.")
                }
                totalBytes += bytes
                if (totalBytes > MAX_TOTAL_PAYLOAD_BYTES) {
                    destination.delete()
                    throw IOException("Selected payloads exceed the 128 MiB build limit.")
                }
                try {
                    validatePayloadElf(destination, displayName)
                } catch (error: Exception) {
                    destination.delete()
                    throw error
                }
                imported.add(
                    mapOf(
                        "name" to displayName.take(MAX_LABEL_LENGTH),
                        "path" to destination.absolutePath,
                        "bytes" to bytes,
                        "sha256" to sha256,
                    ),
                )
            }
            mainHandler.post { result.success(imported) }
        } catch (error: Exception) {
            imported.forEach { (it["path"] as? String)?.let { path -> File(path).delete() } }
            completeError(result, "PAYLOAD_IMPORT_FAILED", error.message ?: "Could not import payload files.")
        }
    }

    private fun displayName(uri: Uri): String {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) return cursor.getString(index)
                }
            }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "payload.elf"
    }

    private fun copyPayload(uri: Uri, destination: File): Pair<Long, String> {
        val digest = MessageDigest.getInstance("SHA-256")
        var copied = 0L
        val input = contentResolver.openInputStream(uri)
            ?: throw IOException("The selected payload could not be opened.")
        try {
            input.use { source ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    while (true) {
                        val count = source.read(buffer)
                        if (count < 0) break
                        copied += count
                        if (copied > MAX_PAYLOAD_BYTES) {
                            throw IOException("Payload exceeds the 64 MiB per-file limit.")
                        }
                        digest.update(buffer, 0, count)
                        output.write(buffer, 0, count)
                    }
                    output.fd.sync()
                }
            }
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
        return copied to digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun runBuild(arguments: Any?, result: MethodChannel.Result) {
        val values = arguments as? Map<*, *>
        val address = values?.get("address") as? String
        val firmware = values?.get("firmware") as? String
        val rawPayloads = values?.get("payloads") as? List<*>
        if (!engineIsInstalled(
                values?.get("version") as? String ?: "",
                values?.get("sha256") as? String ?: "",
            )
        ) {
            result.error("ENGINE_NOT_READY", "Prepare the verified local engine first.", null)
            return
        }
        if (firmware == null || !FIRMWARE_PATTERN.matches(firmware) ||
            address == null || !isPrivateIpv4(address) || rawPayloads == null ||
            rawPayloads.isEmpty() || rawPayloads.size > MAX_PAYLOADS) {
            result.error("INVALID_BUILD_REQUEST", "Choose a private Wi-Fi address and valid ELF payloads.", null)
            return
        }
        try {
            if (firmware !in readSupportedFirmwares(File(filesDir, "engine"))) {
                result.error("UNSUPPORTED_FIRMWARE", "The selected firmware is not supported by this engine.", null)
                return
            }
        } catch (error: Exception) {
            completeError(result, "FIRMWARE_CATALOG_INVALID", error.message ?: "Could not validate firmware.")
            return
        }
        if (buildProcess != null) {
            result.error("BUILD_BUSY", "A local build is already running.", null)
            return
        }

        ioExecutor.execute {
            try {
                val payloads = validatePayloads(rawPayloads)
                val token = createToken()
                val buildDirectory = File(filesDir, "builds/$token")
                if (!buildDirectory.mkdirs()) throw IOException("Could not create the build workspace.")
                val requestFile = File(buildDirectory, "request.json")
                val resultFile = File(buildDirectory, "result.json")
                val requestJson = JSONObject()
                    .put("firmware", firmware)
                    .put("downloadToken", token)
                    .put("address", address)
                    .put("port", 8787)
                    .put("payloads", JSONArray(payloads))
                requestFile.writeText(requestJson.toString())

                val engine = File(filesDir, "engine")
                val nativeLibraries = applicationInfo.nativeLibraryDir
                val nodeExecutable = "$nativeLibraries/libnode.so"
                val dotnetLauncher = "$nativeLibraries/libdotnet-launcher.so"
                val zigExecutable = "$nativeLibraries/libzig.so"
                val buildEnvironment = hashMapOf(
                    "HOME" to buildDirectory.absolutePath,
                    "TMPDIR" to buildDirectory.absolutePath,
                    "PATH" to "$nativeLibraries:/system/bin",
                    "LD_LIBRARY_PATH" to "$nativeLibraries:${engine.path}/node/lib",
                    "OPENSSL_CONF" to "/dev/null",
                    "DOTNET_ROOT" to "${engine.path}/dotnet",
                    "DOTNET" to dotnetLauncher,
                    "SNIPERS_DOTNET_HOSTFXR" to
                        "${engine.path}/dotnet/host/fxr/9.0.20/libhostfxr.so",
                    "DOTNET_MULTILEVEL_LOOKUP" to "0",
                    "DOTNET_SKIP_FIRST_TIME_EXPERIENCE" to "1",
                    "DOTNET_CLI_HOME" to buildDirectory.absolutePath,
                    "NUGET_PACKAGES" to "${buildDirectory.path}/nuget",
                    "PS5_PAYLOAD_SDK" to "${engine.path}/ps5-payload-sdk",
                    "ZIG" to zigExecutable,
                    "ZIG_LIB_DIR" to "${engine.path}/toolchains/zig/lib",
                    "SNIPERS_UFS_DLL" to "${engine.path}/relapse-y2jb/tools/ufs2/publish/ImageBuilder.dll",
                    "SNIPERS_ANDROID_ENGINE" to "1",
                    "SNIPERS_FIRMWARE" to firmware,
                    "DOTNET_GENERATE_ASPNET_CERTIFICATE" to "false",
                    "DOTNET_ADD_GLOBAL_TOOLS_TO_PATH" to "false",
                )
                emitProgress("Đang build image UFS2 cho firmware $firmware.")
                val process = ProcessBuilder(
                    nodeExecutable,
                    "${engine.path}/relapse-host/builder/android-local-build.mjs",
                    requestFile.absolutePath,
                    buildDirectory.absolutePath,
                    resultFile.absolutePath,
                )
                    .directory(engine)
                    .redirectErrorStream(true)
                    .apply { environment().putAll(buildEnvironment) }
                    .start()
                buildProcess = process
                val output = StringBuilder()
                var lastProgressAt = 0L
                var latestProgress: String? = null
                var emittedProgress: String? = null
                process.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        if (output.length > MAX_BUILD_LOG_CHARS) {
                            output.delete(0, output.length - MAX_BUILD_LOG_CHARS / 2)
                        }
                        output.append(line).append('\n')
                        if (line.startsWith("PROGRESS ")) {
                            val progress = line.removePrefix("PROGRESS ")
                                .take(MAX_PROGRESS_LENGTH)
                            latestProgress = progress
                            val now = SystemClock.elapsedRealtime()
                            if (now - lastProgressAt >= PROGRESS_INTERVAL_MS) {
                                emitProgress(progress)
                                emittedProgress = progress
                                lastProgressAt = now
                            }
                        }
                    }
                }
                if (latestProgress != emittedProgress) {
                    latestProgress?.let(::emitProgress)
                }
                val exitCode = process.waitFor()
                buildProcess = null
                if (exitCode != 0) {
                    throw IOException("Local build failed ($exitCode): ${output.toString().takeLast(4000)}")
                }
                if (!resultFile.isFile) throw IOException("Builder did not produce a result manifest.")

                val completed = JSONObject(resultFile.readText())
                val imageFile = File(completed.getString("imagePath"))
                val installerFile = File(completed.getString("installerPath"))
                if (!imageFile.isFile || !installerFile.isFile ||
                    !SHA256_PATTERN.matches(completed.getString("imageSha256")) ||
                    !SHA256_PATTERN.matches(completed.getString("installerSha256"))) {
                    throw IOException("Builder result is missing a verified image or installer.")
                }
                val response = mapOf(
                    "downloadToken" to token,
                    "firmware" to firmware,
                    "imagePath" to imageFile.absolutePath,
                    "imageSha256" to completed.getString("imageSha256"),
                    "imageBytes" to imageFile.length(),
                    "installerPath" to installerFile.absolutePath,
                    "installerSha256" to completed.getString("installerSha256"),
                    "installerBytes" to installerFile.length(),
                    "verifyOnly" to completed.getBoolean("verifyOnly"),
                )
                mainHandler.post { result.success(response) }
            } catch (error: Exception) {
                buildProcess = null
                completeError(result, "LOCAL_BUILD_FAILED", error.message ?: "The local build failed.")
            }
        }
    }

    private fun validatePayloads(rawPayloads: List<*>): List<Map<String, Any>> {
        var totalBytes = 0L
        val hashes = mutableSetOf<String>()
        return rawPayloads.mapIndexed { index, value ->
            val payload = value as? Map<*, *>
                ?: throw IOException("Payload selection $index is invalid.")
            val path = payload["path"] as? String
                ?: throw IOException("Payload selection $index has no file path.")
            val file = File(path).canonicalFile
            val inputDirectory = File(filesDir, "build-inputs").canonicalFile
            if (!file.path.startsWith(inputDirectory.path + File.separator) || !file.isFile) {
                throw IOException("Payload selection $index is outside the private import directory.")
            }
            val name = (payload["name"] as? String)?.take(MAX_LABEL_LENGTH)
                ?: throw IOException("Payload selection $index has no display name.")
            if (!name.endsWith(".elf", ignoreCase = true) &&
                !name.endsWith(".bin", ignoreCase = true)) {
                throw IOException("Payload '$name' is not an ELF or BIN file.")
            }
            val size = file.length()
            if (size < MIN_PAYLOAD_BYTES || size > MAX_PAYLOAD_BYTES) {
                throw IOException("Payload '$name' must be between 64 bytes and 64 MiB.")
            }
            totalBytes += size
            if (totalBytes > MAX_TOTAL_PAYLOAD_BYTES) {
                throw IOException("Selected payloads exceed the 128 MiB build limit.")
            }
            val hash = sha256(file)
            if (hash != payload["sha256"]) {
                throw SecurityException("Payload '$name' changed after import.")
            }
            if (!hashes.add(hash)) {
                throw IOException("The same payload was selected more than once.")
            }
            validatePayloadElf(file, name)
            mapOf(
                "id" to "custom-${(index + 1).toString().padStart(2, '0')}",
                "label" to name,
                "bytes" to size,
                "sha256" to hash,
                "acknowledgement" to "dispatch",
                "path" to file.absolutePath,
            )
        }
    }

    private fun validatePayloadElf(file: File, name: String) {
        RandomAccessFile(file, "r").use { input ->
            if (input.length() < 64) throw IOException("Payload '$name' is too small to be an ELF.")
            val header = ByteArray(64)
            input.readFully(header)
            val elf = ByteBuffer.wrap(header).order(ByteOrder.LITTLE_ENDIAN)
            if (header[0] != 0x7f.toByte() || header[1] != 'E'.code.toByte() ||
                header[2] != 'L'.code.toByte() || header[3] != 'F'.code.toByte() ||
                header[4] != 2.toByte() || header[5] != 1.toByte() ||
                header[6] != 1.toByte() ||
                elf.getShort(16).toInt() !in listOf(2, 3) ||
                elf.getShort(18).toInt() != 62 || elf.getInt(20) != 1 ||
                elf.getShort(52).toInt() != 64 || elf.getShort(54).toInt() != 56) {
                throw IOException("Payload '$name' must be a 64-bit x86 ELF executable.")
            }

            val entry = elf.getLong(24)
            val programOffset = elf.getLong(32)
            val programCount = elf.getShort(56).toInt() and 0xffff
            if (entry < 0 || programOffset < 64 || programCount !in 1..128 ||
                programOffset > input.length() - programCount.toLong() * 56) {
                throw IOException("Payload '$name' has incomplete ELF program headers.")
            }

            var loadSegments = 0
            var executableEntry = false
            var memoryBytes = 0L
            val segment = ByteArray(56)
            repeat(programCount) { index ->
                input.seek(programOffset + index * 56L)
                input.readFully(segment)
                val program = ByteBuffer.wrap(segment).order(ByteOrder.LITTLE_ENDIAN)
                if (program.getInt(0) != 1) return@repeat

                val flags = program.getInt(4)
                val fileOffset = program.getLong(8)
                val virtualAddress = program.getLong(16)
                val fileSize = program.getLong(32)
                val memorySize = program.getLong(40)
                if (fileOffset < 0 || virtualAddress < 0 || fileSize < 0 ||
                    memorySize < fileSize || fileOffset > input.length() - fileSize ||
                    virtualAddress > MAX_ELF_ADDRESS - memorySize) {
                    throw IOException("Payload '$name' has an invalid ELF load segment.")
                }
                memoryBytes = try {
                    Math.addExact(memoryBytes, memorySize)
                } catch (_: ArithmeticException) {
                    throw IOException("Payload '$name' has an excessive ELF memory requirement.")
                }
                loadSegments++
                if (flags and 1 != 0 &&
                    entry >= virtualAddress && entry < virtualAddress + memorySize) {
                    executableEntry = true
                }
            }

            if (loadSegments == 0 || !executableEntry || memoryBytes > MAX_ELF_MEMORY_BYTES) {
                throw IOException("Payload '$name' has an invalid ELF entry point or memory layout.")
            }
        }
    }

    private fun readInstallerAsset(asset: String, result: MethodChannel.Result) {
        val root = File(filesDir, "engine").canonicalFile
        val relativePath = when {
            asset == "install.html" -> "relapse-host/builder/web/install.html"
            asset == "install.js" -> "relapse-host/builder/web/install.js"
            asset == "style.css" -> "relapse-host/builder/web/style.css"
            asset == "autoload.js" -> "relapse-host/site/src/autoload.js"
            asset == "sha256.js" -> "relapse-host/site/src/sha256.js"
            asset.startsWith("runtime/") -> runtimeAssetPath(asset.removePrefix("runtime/"))
            asset.startsWith("ex/runtime/") -> runtimeAssetPath(asset.removePrefix("ex/runtime/"))
            else -> null
        }
        if (relativePath == null) {
            completeError(result, "INSTALLER_ASSET_NOT_FOUND", "The requested PS5 installer page asset is not available.")
            return
        }
        try {
            val file = File(root, relativePath).canonicalFile
            if (!file.path.startsWith(root.path + File.separator) ||
                !file.isFile || file.length() > MAX_INSTALLER_ASSET_BYTES) {
                throw IOException("The PS5 installer page asset is missing or invalid.")
            }
            mainHandler.post { result.success(file.readBytes()) }
        } catch (error: Exception) {
            completeError(result, "INSTALLER_ASSET_READ_FAILED", error.message ?: "Could not read the PS5 installer page asset.")
        }
    }

    private fun runtimeAssetPath(relativePath: String): String? {
        val isRuntimeFile = relativePath == "runtime.js" ||
            Regex("^src/(?:[A-Za-z0-9_-]+/)*[A-Za-z0-9_-]+\\.js$").matches(relativePath) ||
            Regex("^offsets/\\d{1,2}\\.\\d{2}\\.js$").matches(relativePath)
        if (!isRuntimeFile) return null
        return "relapse-host/site/online/2ea9344fcd6fbcb7/$relativePath"
    }

    private fun engineIsInstalled(version: String, sha256: String): Boolean {
        if (!SHA256_PATTERN.matches(sha256)) return false
        return try {
            val state = JSONObject(File(filesDir, ENGINE_STATE_FILE).readText())
            val engine = File(filesDir, "engine")
            state.optString("version") == version &&
                state.optString("sha256") == sha256 &&
                File(engine, "engine.json").isFile &&
                NATIVE_EXECUTABLES.all { File(applicationInfo.nativeLibraryDir, it).canExecute() }
        } catch (_: Exception) {
            false
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun isPrivateIpv4(address: String): Boolean {
        val parts = address.split('.')
        if (parts.size != 4) return false
        val bytes = parts.map { it.toIntOrNull() ?: return false }
        if (bytes.any { it !in 0..255 }) return false
        return bytes[0] == 10 ||
            (bytes[0] == 172 && bytes[1] in 16..31) ||
            (bytes[0] == 192 && bytes[1] == 168)
    }

    private fun createToken(): String {
        val bytes = ByteArray(24)
        SecureRandom().nextBytes(bytes)
        return bytes.joinToString("") { "%02x".format(it) }
    }

    private fun deleteRecursively(file: File) {
        if (!file.exists()) return
        if (file.isDirectory) {
            file.listFiles()?.forEach(::deleteRecursively)
        }
        if (!file.delete()) throw IOException("Could not remove ${file.path}.")
    }

    private fun formatBytes(value: Long): String =
        String.format(Locale.ROOT, "%.1f MiB", value / (1024.0 * 1024.0))

    private fun emitProgress(message: String) {
        mainHandler.post { eventSink?.success(message) }
    }

    private fun completeError(result: MethodChannel.Result, code: String, message: String) {
        Log.e(TAG, "$code: $message")
        mainHandler.post { result.error(code, message, null) }
    }

    override fun onDestroy() {
        buildProcess?.destroy()
        ioExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val METHOD_CHANNEL = "snipers/local_engine"
        private const val EVENT_CHANNEL = "snipers/local_engine/events"
        private const val TAG = "SnipersLocalEngine"
        private const val PICKER_REQUEST = 7513
        private const val ENGINE_STATE_FILE = "engine-state.json"
        private val ENGINE_VERSION_PATTERN = Regex("^\\d+\\.\\d+\\.\\d+$")
        private val SOURCE_TAG_PATTERN = Regex("^v\\d+\\.\\d+\\.\\d+$")
        private val FIRMWARE_PATTERN = Regex("^\\d{1,2}\\.\\d{2}$")
        private val NATIVE_EXECUTABLES = listOf("libnode.so", "libdotnet.so", "libzig.so")
        private const val GITHUB_LATEST_RELEASE_URL =
            "https://api.github.com/repos/GronedWaffel/snipers-youtube-builder/releases/latest"
        private const val MAX_ENGINE_ARCHIVE_BYTES = 500L * 1024 * 1024
        private const val MAX_ENGINE_UNPACKED_BYTES = 1024L * 1024 * 1024
        private const val MAX_SOURCE_ARCHIVE_BYTES = 100L * 1024 * 1024
        private const val MAX_SOURCE_CATALOG_BYTES = 4 * 1024 * 1024
        private const val MAX_RELEASE_JSON_BYTES = 2 * 1024 * 1024
        private const val MAX_INSTALLER_ASSET_BYTES = 4L * 1024 * 1024
        private const val MAX_FIRMWARE_PROFILES = 64
        private const val NETWORK_CONNECT_TIMEOUT_MS = 15000
        private const val NETWORK_READ_TIMEOUT_MS = 60000
        private const val MAX_PAYLOADS = 8
        private const val MIN_PAYLOAD_BYTES = 64L
        private const val MAX_PAYLOAD_BYTES = 64L * 1024 * 1024
        private const val MAX_TOTAL_PAYLOAD_BYTES = 128L * 1024 * 1024
        private const val MAX_ELF_ADDRESS = 0x800000000000L
        private const val MAX_ELF_MEMORY_BYTES = 512L * 1024 * 1024
        private const val MAX_LABEL_LENGTH = 180
        private const val MAX_BUILD_LOG_CHARS = 16000
        private const val MAX_PROGRESS_LENGTH = 500
        private const val PROGRESS_INTERVAL_MS = 250L
        private val SHA256_PATTERN = Regex("^[a-f0-9]{64}$")
    }
}
