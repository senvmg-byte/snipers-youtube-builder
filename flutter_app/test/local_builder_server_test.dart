import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snipers_youtube_builder/local_builder_server.dart';

const buildToken = '0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  late LocalBuilderServer server;
  late HttpClient client;
  late Uri baseUri;
  late Directory temporaryDirectory;
  late Directory buildDirectory;
  late File imageFile;
  late File installerFile;
  late File importedPayload;
  bool? cleanupAfterInstall;
  var proxiedPackageRequests = 0;
  String? proxiedPackageFirmware;

  setUp(() async {
    temporaryDirectory =
        await Directory.systemTemp.createTemp('snipers-lan-test-');
    buildDirectory = Directory('${temporaryDirectory.path}/builds/$buildToken');
    await Directory('${buildDirectory.path}/image').create(recursive: true);
    imageFile = File('${buildDirectory.path}/image/download0.dat');
    installerFile =
        File('${buildDirectory.path}/Snipers-YouTube-Installer.elf');
    await imageFile.writeAsBytes([1, 2, 3, 4]);
    await installerFile.writeAsBytes([5, 6, 7]);
    importedPayload =
        File('${temporaryDirectory.path}/build-inputs/payload.elf');
    await importedPayload.parent.create(recursive: true);
    await importedPayload.writeAsBytes([8, 9]);
    cleanupAfterInstall = null;
    proxiedPackageRequests = 0;
    proxiedPackageFirmware = null;
    server = LocalBuilderServer(
      port: 0,
      addressProvider: () async => [InternetAddress.loopbackIPv4],
      assetReader: (asset) async => utf8.encode('offline asset: $asset'),
      youtubePackageProxy: (request, response, firmware) async {
        proxiedPackageRequests++;
        proxiedPackageFirmware = firmware;
        if (request.method == 'HEAD') {
          response.headers.contentLength = 101515264;
          await response.close();
          return;
        }
        final range = request.headers.value(HttpHeaders.rangeHeader);
        if (range == 'bytes=0-6') {
          response
            ..statusCode = HttpStatus.partialContent
            ..headers.set('content-range', 'bytes 0-6/101515264')
            ..headers.contentLength = 7
            ..add(utf8.encode('pkgdata'));
          await response.close();
          return;
        }
        response
          ..headers.contentLength = 7
          ..add(utf8.encode('pkgdata'));
        await response.close();
      },
      onBuildCleaned: (afterInstall) async {
        cleanupAfterInstall = afterInstall;
      },
    );
    client = HttpClient();
    await server.start();
    baseUri = server.urls.single;
  });

  tearDown(() async {
    client.close(force: true);
    await server.stop();
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('serves the LAN landing page and discloses build readiness', () async {
    final pageResponse =
        await client.getUrl(baseUri).then((request) => request.close());
    expect(pageResponse.statusCode, HttpStatus.ok);
    expect(await utf8.decoder.bind(pageResponse).join(),
        contains('Máy chủ nội bộ'));

    final statusUri = baseUri.replace(path: '/api/status');
    final statusResponse =
        await client.getUrl(statusUri).then((request) => request.close());
    final status = jsonDecode(await utf8.decoder.bind(statusResponse).join())
        as Map<String, dynamic>;

    expect(statusResponse.statusCode, HttpStatus.ok);
    expect(status['lanServer'], isTrue);
    expect(status['offlineBuildReady'], isFalse);
  });

  test('rejects writes and unknown routes', () async {
    final postRequest = await client.postUrl(baseUri);
    final postResponse = await postRequest.close();
    expect(postResponse.statusCode, HttpStatus.methodNotAllowed);
    expect(postResponse.headers.value(HttpHeaders.allowHeader), 'GET');

    final missingUri = baseUri.replace(path: '/missing');
    final missingResponse =
        await client.getUrl(missingUri).then((request) => request.close());
    expect(missingResponse.statusCode, HttpStatus.notFound);
  });

  test('manual cleanup removes the build workspace and keeps imported payloads',
      () async {
    server
      ..setEngineReady(true)
      ..publishBuild(
        downloadToken: buildToken,
        imagePath: imageFile.path,
        installerPath: installerFile.path,
        firmware: '13.60',
        installerSha256: 'a' * 64,
        payloadNames: const ['custom.elf'],
        verifyOnly: false,
      );

    final releasedBytes = await server.cleanBuild();

    expect(releasedBytes, 7);
    expect(await buildDirectory.exists(), isFalse);
    expect(await importedPayload.readAsBytes(), [8, 9]);
    expect(server.offlineBuildReady, isFalse);
    expect(cleanupAfterInstall, isFalse);
  });

  test('serves only the offset table matching the published firmware',
      () async {
    server
      ..setEngineReady(true)
      ..publishBuild(
        downloadToken: buildToken,
        imagePath: imageFile.path,
        installerPath: installerFile.path,
        firmware: '13.60',
        installerSha256: 'a' * 64,
        payloadNames: const ['custom.elf'],
        verifyOnly: false,
      );

    final offsetsUri = baseUri.replace(path: '/offsets/13.60.js');
    final offsetsResponse =
        await client.getUrl(offsetsUri).then((request) => request.close());
    expect(offsetsResponse.statusCode, HttpStatus.ok);
    expect(
      offsetsResponse.headers.contentType?.mimeType,
      'text/javascript',
    );
    expect(
      await utf8.decoder.bind(offsetsResponse).join(),
      'offline asset: runtime/offsets/13.60.js',
    );

    final mismatchedOffsetsUri = baseUri.replace(path: '/offsets/13.20.js');
    final mismatchedOffsetsResponse = await client
        .getUrl(mismatchedOffsetsUri)
        .then((request) => request.close());
    expect(mismatchedOffsetsResponse.statusCode, HttpStatus.notFound);
  });

  test('serves the PS5 browser worker at its resolved root-relative URL',
      () async {
    server
      ..setEngineReady(true)
      ..publishBuild(
        downloadToken: buildToken,
        imagePath: imageFile.path,
        installerPath: installerFile.path,
        firmware: '13.60',
        installerSha256: 'a' * 64,
        payloadNames: const ['custom.elf'],
        verifyOnly: false,
      );

    final workerUri = baseUri.replace(path: '/src/utils/rop_slave.js');
    final workerResponse =
        await client.getUrl(workerUri).then((request) => request.close());

    expect(workerResponse.statusCode, HttpStatus.ok);
    expect(
      workerResponse.headers.contentType?.mimeType,
      'text/javascript',
    );
    expect(
      await utf8.decoder.bind(workerResponse).join(),
      'offline asset: runtime/src/utils/rop_slave.js',
    );
  });

  test('proxies the pinned YouTube package only for a real published build',
      () async {
    server
      ..setEngineReady(true)
      ..publishBuild(
        downloadToken: buildToken,
        imagePath: imageFile.path,
        installerPath: installerFile.path,
        firmware: '13.60',
        installerSha256: 'a' * 64,
        payloadNames: const ['custom.elf'],
        verifyOnly: false,
      );

    final packageResponse = await client
        .getUrl(baseUri.replace(
          path: '/youtube-packages/YouTube-PPSA01650-01.000.030.pkg',
        ))
        .then((request) => request.close());

    expect(packageResponse.statusCode, HttpStatus.ok);
    expect(await utf8.decoder.bind(packageResponse).join(), 'pkgdata');
    expect(proxiedPackageRequests, 1);
    expect(proxiedPackageFirmware, '13.60');

    final rangeRequest = await client.getUrl(baseUri.replace(
      path: '/youtube-packages/YouTube-PPSA01650-01.000.030.pkg',
    ));
    rangeRequest.headers.set(HttpHeaders.rangeHeader, 'bytes=0-6');
    final rangeResponse = await rangeRequest.close();
    expect(rangeResponse.statusCode, HttpStatus.partialContent);
    expect(
        rangeResponse.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(
      rangeResponse.headers.value(HttpHeaders.contentRangeHeader),
      'bytes 0-6/101515264',
    );
    expect(await utf8.decoder.bind(rangeResponse).join(), 'pkgdata');
    expect(proxiedPackageRequests, 2);

    final headResponse = await client
        .headUrl(baseUri.replace(
          path: '/youtube-packages/YouTube-PPSA01650-01.000.030.pkg',
        ))
        .then((request) => request.close());
    expect(headResponse.statusCode, HttpStatus.ok);
    expect(headResponse.headers.contentLength, 101515264);
    expect(headResponse.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    expect(await utf8.decoder.bind(headResponse).join(), isEmpty);
    expect(proxiedPackageRequests, 3);

    final wrongVersionResponse = await client
        .getUrl(baseUri.replace(
          path: '/youtube-packages/YouTube-PPSA01650-01.000.003.pkg',
        ))
        .then((request) => request.close());
    expect(wrongVersionResponse.statusCode, HttpStatus.notFound);
    expect(proxiedPackageRequests, 3);
  });

  test('does not proxy YouTube packages for verification-only builds',
      () async {
    server
      ..setEngineReady(true)
      ..publishBuild(
        downloadToken: buildToken,
        imagePath: imageFile.path,
        installerPath: installerFile.path,
        firmware: '13.60',
        installerSha256: 'a' * 64,
        payloadNames: const ['custom.elf'],
        verifyOnly: true,
      );

    final packageResponse = await client
        .getUrl(baseUri.replace(
          path: '/youtube-packages/YouTube-PPSA01650-01.000.030.pkg',
        ))
        .then((request) => request.close());

    expect(packageResponse.statusCode, HttpStatus.notFound);
    expect(proxiedPackageRequests, 0);
  });

  test('serves every PS5 installer runtime URL through both runtime aliases',
      () async {
    server
      ..setEngineReady(true)
      ..publishBuild(
        downloadToken: buildToken,
        imagePath: imageFile.path,
        installerPath: installerFile.path,
        firmware: '13.60',
        installerSha256: 'a' * 64,
        payloadNames: const ['custom.elf'],
        verifyOnly: false,
      );

    final runtimePaths = <String, String>{
      '/builder/runtime/runtime.js': 'runtime/runtime.js',
      '/builder/runtime/src/sha256.js': 'runtime/src/sha256.js',
      '/builder/runtime/src/webkit.js': 'runtime/src/webkit.js',
      '/builder/runtime/src/utils/mem.js': 'runtime/src/utils/mem.js',
      '/builder/ex/runtime/src/firmware.js': 'ex/runtime/src/firmware.js',
      '/builder/ex/runtime/src/utils/syscalls.js':
          'ex/runtime/src/utils/syscalls.js',
      '/builder/ex/runtime/src/rop.js': 'ex/runtime/src/rop.js',
      '/builder/ex/runtime/src/main.js': 'ex/runtime/src/main.js',
      '/builder/runtime/offsets/13.60.js': 'runtime/offsets/13.60.js',
    };

    for (final entry in runtimePaths.entries) {
      final response = await client
          .getUrl(baseUri.replace(path: entry.key))
          .then((request) => request.close());
      expect(response.statusCode, HttpStatus.ok, reason: entry.key);
      expect(
        response.headers.contentType?.mimeType,
        'text/javascript',
        reason: entry.key,
      );
      expect(
        await utf8.decoder.bind(response).join(),
        'offline asset: ${entry.value}',
        reason: entry.key,
      );
    }

    final runtimeApiResponse = await client
        .getUrl(baseUri.replace(path: '/api/runtime'))
        .then((request) => request.close());
    final catalog = jsonDecode(
      await utf8.decoder.bind(runtimeApiResponse).join(),
    ) as Map<String, dynamic>;
    expect(runtimeApiResponse.statusCode, HttpStatus.ok);
    expect(catalog['runtime'], '/builder/runtime/runtime.js');
    expect(catalog['base'], '/builder/runtime/');
  });

  test('serves only the published build files through their LAN routes',
      () async {
    server
      ..setEngineReady(true)
      ..publishBuild(
        downloadToken: buildToken,
        imagePath: imageFile.path,
        installerPath: installerFile.path,
        firmware: '13.60',
        installerSha256: 'a' * 64,
        payloadNames: const ['custom.elf'],
        verifyOnly: false,
      );

    final statusUri = baseUri.replace(path: '/api/status');
    final statusResponse =
        await client.getUrl(statusUri).then((request) => request.close());
    final status = jsonDecode(await utf8.decoder.bind(statusResponse).join())
        as Map<String, dynamic>;
    expect(status['offlineBuildReady'], isTrue);
    expect(status['imageUrl'], '/builder/youtube-bundles/$buildToken.dat');
    expect(status['installerUrl'], '/builder/installer.elf');
    expect(status['installCode'], '0123456789');
    expect(
      status['installPageUrl'],
      '/install?code=0123456789',
    );

    final pageUri = baseUri.replace(
      path: '/install',
      queryParameters: {'code': '0123456789'},
    );
    final pageResponse =
        await client.getUrl(pageUri).then((request) => request.close());
    expect(pageResponse.statusCode, HttpStatus.ok);
    expect(
      await utf8.decoder.bind(pageResponse).join(),
      'offline asset: install.html',
    );

    final runtimeUri = baseUri.replace(path: '/api/runtime');
    final runtimeResponse =
        await client.getUrl(runtimeUri).then((request) => request.close());
    final runtime = jsonDecode(await utf8.decoder.bind(runtimeResponse).join())
        as Map<String, dynamic>;
    expect(runtime['runtime'], '/builder/runtime/runtime.js');
    expect(runtime['base'], '/builder/runtime/');

    final codeUri = baseUri.replace(path: '/api/install/0123456789');
    final codeResponse =
        await client.getUrl(codeUri).then((request) => request.close());
    final code = jsonDecode(await utf8.decoder.bind(codeResponse).join())
        as Map<String, dynamic>;
    expect(code['firmware'], '13.60');
    expect(code['download'], '/installers/$buildToken.elf');
    expect(code['sha256'], 'a' * 64);
    expect(code['payloads'], ['custom.elf']);
    expect(code['verifyOnly'], isFalse);

    final imageUri =
        baseUri.replace(path: '/builder/youtube-bundles/$buildToken.dat');
    final imageResponse =
        await client.getUrl(imageUri).then((request) => request.close());
    expect(imageResponse.statusCode, HttpStatus.ok);
    expect(imageResponse.headers.contentLength, 4);
    expect(imageResponse.headers.value('content-disposition'),
        'attachment; filename="download0.dat"');
    expect(
        await imageResponse
            .fold<List<int>>([], (bytes, part) => bytes..addAll(part)),
        [1, 2, 3, 4]);

    final installerUri = baseUri.replace(path: '/builder/installer.elf');
    final installerResponse =
        await client.getUrl(installerUri).then((request) => request.close());
    expect(installerResponse.statusCode, HttpStatus.ok);
    expect(
      await installerResponse
          .fold<List<int>>([], (bytes, part) => bytes..addAll(part)),
      [5, 6, 7],
    );

    final installerRouteUri =
        baseUri.replace(path: '/installers/$buildToken.elf');
    final installerRouteResponse = await client
        .getUrl(installerRouteUri)
        .then((request) => request.close());
    expect(installerRouteResponse.statusCode, HttpStatus.ok);

    final ps5Request = await client.getUrl(baseUri);
    ps5Request
      ..followRedirects = false
      ..headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 PlayStation 5/13.60',
      );
    final ps5Response = await ps5Request.close();
    expect(ps5Response.statusCode, HttpStatus.found);
    expect(
      ps5Response.headers.value(HttpHeaders.locationHeader),
      '/install?code=0123456789',
    );

    final cleanupRequest = await client.postUrl(
      baseUri.replace(path: '/api/install/0123456789/complete'),
    );
    final cleanupResponse = await cleanupRequest.close();
    final cleanup = jsonDecode(
      await utf8.decoder.bind(cleanupResponse).join(),
    ) as Map<String, dynamic>;
    expect(cleanupResponse.statusCode, HttpStatus.ok);
    expect(cleanup['releasedBytes'], 7);
    expect(await buildDirectory.exists(), isFalse);
    expect(await importedPayload.readAsBytes(), [8, 9]);
    expect(cleanupAfterInstall, isTrue);

    final clearedResponse =
        await client.getUrl(imageUri).then((request) => request.close());
    expect(clearedResponse.statusCode, HttpStatus.notFound);
  });
}
