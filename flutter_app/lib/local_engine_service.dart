import 'dart:convert';

import 'package:flutter/services.dart';

class EngineManifest {
  const EngineManifest({
    required this.version,
    required this.sourceTag,
    required this.archive,
    required this.sha256,
    required this.bytes,
    required this.uncompressedBytes,
    required this.firmware,
  });

  final String version;
  final String sourceTag;
  final String archive;
  final String sha256;
  final int bytes;
  final int uncompressedBytes;
  final List<String> firmware;

  static Future<EngineManifest> load() async {
    final decoded = jsonDecode(
      await rootBundle.loadString('assets/engine/manifest.json'),
    );
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid local engine manifest.');
    }
    final version = decoded['version'];
    final sourceTag = decoded['sourceTag'];
    final archive = decoded['archive'];
    final sha256 = decoded['sha256'];
    final bytes = decoded['bytes'];
    final uncompressedBytes = decoded['uncompressedBytes'];
    final firmware = decoded['firmware'];
    if (version is! String ||
        sourceTag is! String ||
        !RegExp(r'^v\d+\.\d+\.\d+$').hasMatch(sourceTag) ||
        archive is! String ||
        sha256 is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        bytes is! int ||
        bytes <= 0 ||
        uncompressedBytes is! int ||
        uncompressedBytes <= 0 ||
        firmware is! List ||
        firmware.any((item) =>
            item is! String || !RegExp(r'^\d{1,2}\.\d{2}$').hasMatch(item)) ||
        firmware.toSet().length != firmware.length) {
      throw const FormatException('Local engine manifest fields are invalid.');
    }
    return EngineManifest(
      version: version,
      sourceTag: sourceTag,
      archive: archive,
      sha256: sha256,
      bytes: bytes,
      uncompressedBytes: uncompressedBytes,
      firmware: firmware.cast<String>(),
    );
  }

  Map<String, Object> toMap() => {
        'version': version,
        'sourceTag': sourceTag,
        'archive': archive,
        'sha256': sha256,
        'bytes': bytes,
        'uncompressedBytes': uncompressedBytes,
        'firmware': firmware,
      };
}

class LocalPayload {
  const LocalPayload({
    required this.name,
    required this.path,
    required this.bytes,
    required this.sha256,
  });

  final String name;
  final String path;
  final int bytes;
  final String sha256;

  factory LocalPayload.fromMap(Map<Object?, Object?> value) {
    final name = value['name'];
    final path = value['path'];
    final bytes = value['bytes'];
    final sha256 = value['sha256'];
    if (name is! String || path is! String || bytes is! int || sha256 is! String) {
      throw const FormatException('Invalid imported payload metadata.');
    }
    return LocalPayload(
      name: name,
      path: path,
      bytes: bytes,
      sha256: sha256,
    );
  }

  Map<String, Object> toMap() => {
        'name': name,
        'path': path,
        'bytes': bytes,
        'sha256': sha256,
      };
}

class LocalBuildResult {
  const LocalBuildResult({
    required this.downloadToken,
    required this.imagePath,
    required this.imageSha256,
    required this.imageBytes,
    required this.installerPath,
    required this.installerSha256,
    required this.installerBytes,
    required this.firmware,
    required this.verifyOnly,
  });

  final String downloadToken;
  final String imagePath;
  final String imageSha256;
  final int imageBytes;
  final String installerPath;
  final String installerSha256;
  final int installerBytes;
  final String firmware;
  final bool verifyOnly;

  factory LocalBuildResult.fromMap(Map<Object?, Object?> value) {
    final token = value['downloadToken'];
    final imagePath = value['imagePath'];
    final imageSha256 = value['imageSha256'];
    final imageBytes = value['imageBytes'];
    final installerPath = value['installerPath'];
    final installerSha256 = value['installerSha256'];
    final installerBytes = value['installerBytes'];
    final firmware = value['firmware'];
    final verifyOnly = value['verifyOnly'];
    if (token is! String ||
        imagePath is! String ||
        imageSha256 is! String ||
        imageBytes is! int ||
        installerPath is! String ||
        installerSha256 is! String ||
        installerBytes is! int ||
        installerBytes <= 0 ||
        firmware is! String ||
        verifyOnly is! bool) {
      throw const FormatException('Invalid local build result.');
    }
    return LocalBuildResult(
      downloadToken: token,
      imagePath: imagePath,
      imageSha256: imageSha256,
      imageBytes: imageBytes,
      installerPath: installerPath,
      installerSha256: installerSha256,
      installerBytes: installerBytes,
      firmware: firmware,
      verifyOnly: verifyOnly,
    );
  }
}

class UpstreamSourceRelease {
  const UpstreamSourceRelease({
    required this.currentTag,
    required this.latestTag,
    required this.name,
    required this.sourceBytes,
    required this.sourceSha256,
    required this.updateAvailable,
  });

  final String currentTag;
  final String latestTag;
  final String name;
  final int sourceBytes;
  final String sourceSha256;
  final bool updateAvailable;

  factory UpstreamSourceRelease.fromMap(Map<Object?, Object?> value) {
    final currentTag = value['currentTag'];
    final latestTag = value['latestTag'];
    final name = value['name'];
    final sourceBytes = value['sourceBytes'];
    final sourceSha256 = value['sourceSha256'];
    final updateAvailable = value['updateAvailable'];
    if (currentTag is! String ||
        latestTag is! String ||
        name is! String ||
        sourceBytes is! int ||
        sourceBytes <= 0 ||
        sourceSha256 is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sourceSha256) ||
        updateAvailable is! bool) {
      throw const FormatException('Invalid GitHub source release metadata.');
    }
    return UpstreamSourceRelease(
      currentTag: currentTag,
      latestTag: latestTag,
      name: name,
      sourceBytes: sourceBytes,
      sourceSha256: sourceSha256,
      updateAvailable: updateAvailable,
    );
  }
}

class LocalEngineService {
  static const _methods = MethodChannel('snipers/local_engine');
  static const _events = EventChannel('snipers/local_engine/events');

  Stream<String> get progress =>
      _events.receiveBroadcastStream().map((event) => event as String);

  Future<bool> isInstalled(EngineManifest manifest) async {
    final installed = await _methods.invokeMethod<bool>(
      'engineStatus',
      {'version': manifest.version, 'sha256': manifest.sha256},
    );
    return installed ?? false;
  }

  Future<void> prepare(EngineManifest manifest) async {
    await _methods.invokeMethod<Map<Object?, Object?>>(
      'prepareEngine',
      manifest.toMap(),
    );
  }

  Future<List<String>> supportedFirmwares() async {
    final firmwares =
        await _methods.invokeListMethod<String>('supportedFirmwares');
    if (firmwares == null ||
        firmwares.isEmpty ||
        firmwares.any((firmware) =>
            !RegExp(r'^\d{1,2}\.\d{2}$').hasMatch(firmware))) {
      throw const FormatException('The local engine firmware catalog is invalid.');
    }
    return List<String>.unmodifiable(firmwares);
  }

  Future<Uint8List> readInstallerAsset(String asset) async {
    final bytes = await _methods.invokeMethod<Uint8List>(
      'readInstallerAsset',
      asset,
    );
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('The offline PS5 installer page asset is empty.');
    }
    return bytes;
  }

  Future<UpstreamSourceRelease> checkUpstreamSource(
      EngineManifest manifest) async {
    final release = await _methods.invokeMapMethod<Object?, Object?>(
      'checkUpstreamSource',
      {'bundledTag': manifest.sourceTag},
    );
    if (release == null) {
      throw const FormatException('GitHub did not return a source release.');
    }
    return UpstreamSourceRelease.fromMap(release);
  }

  Future<UpstreamSourceRelease> updateUpstreamSource(
      EngineManifest manifest, String tag) async {
    final release = await _methods.invokeMapMethod<Object?, Object?>(
      'updateUpstreamSource',
      {'tag': tag, 'bundledTag': manifest.sourceTag},
    );
    if (release == null) {
      throw const FormatException('GitHub source update returned no result.');
    }
    return UpstreamSourceRelease.fromMap(release);
  }

  Future<List<LocalPayload>> selectPayloads() async {
    final selected = await _methods.invokeMethod<List<Object?>>('pickPayloads');
    if (selected == null) return const [];
    return selected
        .map((item) => LocalPayload.fromMap(item! as Map<Object?, Object?>))
        .toList(growable: false);
  }

  Future<LocalBuildResult> build({
    required EngineManifest manifest,
    required String firmware,
    required String address,
    required List<LocalPayload> payloads,
  }) async {
    final result = await _methods.invokeMapMethod<Object?, Object?>(
      'runBuild',
      {
        'version': manifest.version,
        'sha256': manifest.sha256,
        'firmware': firmware,
        'address': address,
        'payloads': payloads.map((payload) => payload.toMap()).toList(),
      },
    );
    if (result == null) {
      throw const FormatException('Local build returned no result.');
    }
    return LocalBuildResult.fromMap(result);
  }
}
