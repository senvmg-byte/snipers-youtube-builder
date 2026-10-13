import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalBuilderServer {
  LocalBuilderServer({
    this.port = 8787,
    Future<List<InternetAddress>> Function()? addressProvider,
    this.assetReader,
    this.youtubePackageProxy,
    this.onBuildCleaned,
  }) : _addressProvider = addressProvider ?? _wifiAddresses;

  final int port;
  final Future<List<InternetAddress>> Function() _addressProvider;
  final Future<List<int>> Function(String asset)? assetReader;
  final Future<void> Function(
    HttpRequest request,
    HttpResponse response,
    String firmware,
  )? youtubePackageProxy;
  final Future<void> Function(bool afterInstall)? onBuildCleaned;
  final List<HttpServer> _servers = [];
  bool _engineReady = false;
  String? _downloadToken;
  File? _imageFile;
  File? _installerFile;
  String? _firmware;
  String? _installerSha256;
  List<String> _payloadNames = const [];
  bool _verifyOnly = true;

  bool get isRunning => _servers.isNotEmpty;
  bool get offlineBuildReady =>
      _engineReady &&
      _downloadToken != null &&
      _imageFile != null &&
      _installerFile != null;

  List<Uri> get urls => [
        for (final server in _servers)
          Uri(
            scheme: 'http',
            host: server.address.address,
            port: server.port,
          ),
      ];

  Future<void> start() async {
    if (isRunning) return;

    final addresses = await _addressProvider();
    if (addresses.isEmpty) {
      throw StateError(
        'Không tìm thấy địa chỉ IPv4 riêng trên Wi-Fi. '
        'Hãy kết nối điện thoại và PS5 cùng một mạng Wi-Fi.',
      );
    }

    try {
      for (final address in addresses) {
        final server = await HttpServer.bind(address, port);
        _servers.add(server);
        server.listen((request) {
          unawaited(_handleRequest(request));
        });
      }
    } catch (_) {
      await stop();
      rethrow;
    }
  }

  Future<void> stop() async {
    final servers = List<HttpServer>.of(_servers);
    _servers.clear();
    await Future.wait(servers.map((server) => server.close(force: true)));
  }

  void setEngineReady(bool ready) {
    _engineReady = ready;
    if (!ready) clearBuild();
  }

  void publishBuild({
    required String downloadToken,
    required String imagePath,
    required String installerPath,
    required String firmware,
    required String installerSha256,
    required List<String> payloadNames,
    required bool verifyOnly,
  }) {
    if (!RegExp(r'^[a-f0-9]{48}$').hasMatch(downloadToken)) {
      throw ArgumentError.value(
          downloadToken, 'downloadToken', 'Invalid build token.');
    }
    final imageFile = File(imagePath);
    final installerFile = File(installerPath);
    if (!imageFile.existsSync() || !installerFile.existsSync()) {
      throw StateError('The completed build files are not available.');
    }
    final buildDirectory = imageFile.parent.parent;
    final normalizedImagePath = imageFile.absolute.path.replaceAll('\\', '/');
    final normalizedBuildPath =
        buildDirectory.absolute.path.replaceAll('\\', '/');
    final normalizedInstallerPath =
        installerFile.absolute.path.replaceAll('\\', '/');
    if (!normalizedImagePath.endsWith(
          '/builds/$downloadToken/image/download0.dat',
        ) ||
        normalizedInstallerPath !=
            '$normalizedBuildPath/Snipers-YouTube-Installer.elf') {
      throw ArgumentError(
          'Build files are outside the expected private workspace.');
    }
    _downloadToken = downloadToken;
    _imageFile = imageFile;
    _installerFile = installerFile;
    _firmware = firmware;
    _installerSha256 = installerSha256;
    _payloadNames = List<String>.unmodifiable(payloadNames);
    _verifyOnly = verifyOnly;
  }

  void clearBuild() {
    _downloadToken = null;
    _imageFile = null;
    _installerFile = null;
    _firmware = null;
    _installerSha256 = null;
    _payloadNames = const [];
    _verifyOnly = true;
  }

  Future<int?> cleanBuild({bool afterInstall = false}) async {
    final imageFile = _imageFile;
    if (!offlineBuildReady || imageFile == null) return null;

    final buildDirectory = imageFile.parent.parent;
    var releasedBytes = 0;
    try {
      await for (final entry
          in buildDirectory.list(recursive: true, followLinks: false)) {
        if (entry is File) releasedBytes += await entry.length();
      }
      await buildDirectory.delete(recursive: true);
      clearBuild();
      await onBuildCleaned?.call(afterInstall);
      return releasedBytes;
    } on FileSystemException catch (error, stackTrace) {
      stderr.writeln('Failed to clean local build: $error\n$stackTrace');
      rethrow;
    } on Exception catch (error, stackTrace) {
      stderr
          .writeln('Failed to finish local build cleanup: $error\n$stackTrace');
      rethrow;
    }
  }

  String _installCode(String token) => token.substring(0, 10).toUpperCase();

  static String? _youtubePackageVersion(String firmware) {
    final match = RegExp(r'^(\d{1,2})\.(\d{2})$').firstMatch(firmware);
    if (match == null) return null;
    final major = int.parse(match.group(1)!);
    final minor = int.parse(match.group(2)!);
    return major > 12 || (major == 12 && minor >= 60)
        ? '01.000.030'
        : '01.000.003';
  }

  static String? _youtubePackagePath(String firmware) {
    final version = _youtubePackageVersion(firmware);
    return version == null
        ? null
        : '/youtube-packages/YouTube-PPSA01650-$version.pkg';
  }

  static int _youtubePackageBytes(String version) =>
      version == '01.000.030' ? 101515264 : 107544576;

  Future<void> _serveYoutubePackage(
    HttpRequest request,
    HttpResponse response,
    String firmware,
  ) async {
    final version = _youtubePackageVersion(firmware);
    if (version == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    var responseStarted = false;
    try {
      final upstreamRequest = await client
          .openUrl(
            request.method,
            Uri.https(
              'sniperscheats.lol',
              '/builder/youtube-packages/YouTube-PPSA01650-$version.pkg',
            ),
          )
          .timeout(const Duration(seconds: 20));
      final range = request.method == 'GET'
          ? request.headers.value(HttpHeaders.rangeHeader)
          : null;
      upstreamRequest
        ..followRedirects = false
        ..headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (range != null) {
        upstreamRequest.headers.set(HttpHeaders.rangeHeader, range);
        final ifRange = request.headers.value('if-range');
        if (ifRange != null) upstreamRequest.headers.set('if-range', ifRange);
      }
      final upstream =
          await upstreamRequest.close().timeout(const Duration(seconds: 30));
      final expectedBytes = _youtubePackageBytes(version);
      final isHead = request.method == 'HEAD';
      final contentRange = upstream.headers.value('content-range');
      final partialRange = range == null
          ? null
          : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(
              contentRange ?? '',
            );
      final partialLength = partialRange == null
          ? null
          : int.parse(partialRange.group(2)!) -
              int.parse(partialRange.group(1)!) +
              1;
      final validPartialResponse = partialRange != null &&
          int.parse(partialRange.group(1)!) <=
              int.parse(partialRange.group(2)!) &&
          int.parse(partialRange.group(2)!) < expectedBytes &&
          int.parse(partialRange.group(3)!) == expectedBytes &&
          upstream.contentLength == partialLength;
      final validFullResponse = upstream.statusCode == HttpStatus.ok &&
          upstream.contentLength == expectedBytes;
      final validPartialStatus =
          range != null && upstream.statusCode == HttpStatus.partialContent;
      final validUnsatisfiableRange = range != null &&
          upstream.statusCode == HttpStatus.requestedRangeNotSatisfiable &&
          contentRange == 'bytes */$expectedBytes';
      if (validUnsatisfiableRange) {
        response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
          ..headers.set('content-range', contentRange!);
        if (upstream.contentLength >= 0) {
          response.headers.contentLength = upstream.contentLength;
        }
        await upstream.drain<void>();
        await response.close();
        return;
      }
      if (isHead) {
        if (upstream.statusCode != HttpStatus.ok ||
            upstream.contentLength != expectedBytes) {
          await upstream.drain<void>();
          response.statusCode = HttpStatus.badGateway;
          await response.close();
          return;
        }
      } else if (!(validFullResponse && range == null) &&
          !(validPartialStatus && validPartialResponse)) {
        await upstream.drain<void>();
        response
          ..statusCode = HttpStatus.badGateway
          ..headers.contentType = ContentType.text
          ..write('Pinned YouTube package is unavailable upstream.');
        await response.close();
        return;
      }

      response
        ..statusCode = upstream.statusCode
        ..headers.contentType = ContentType('application', 'octet-stream')
        ..headers.set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..headers.contentLength = upstream.contentLength;
      if (contentRange != null) {
        response.headers.set('content-range', contentRange);
      }
      final etag = upstream.headers.value(HttpHeaders.etagHeader);
      if (etag != null) response.headers.set(HttpHeaders.etagHeader, etag);
      final lastModified =
          upstream.headers.value(HttpHeaders.lastModifiedHeader);
      if (lastModified != null) {
        response.headers.set(HttpHeaders.lastModifiedHeader, lastModified);
      }
      if (isHead) {
        await upstream.drain<void>();
        await response.close();
        return;
      }
      responseStarted = true;
      await response.addStream(upstream.timeout(const Duration(seconds: 60)));
      await response.close();
    } on Exception catch (error, stackTrace) {
      stderr.writeln('Failed to proxy YouTube package: $error\n$stackTrace');
      if (responseStarted) {
        try {
          await response.close();
        } on Exception catch (closeError, closeStackTrace) {
          stderr.writeln(
            'Failed to close proxied YouTube package: '
            '$closeError\n$closeStackTrace',
          );
        }
      } else {
        response
          ..statusCode = HttpStatus.badGateway
          ..headers.contentType = ContentType.text
          ..write('Could not reach the pinned YouTube package source.');
        await response.close();
      }
    } finally {
      client.close(force: true);
    }
  }

  String? _runtimeAssetPath(String path) {
    if (path.startsWith('/builder/runtime/')) {
      return 'runtime/${path.substring('/builder/runtime/'.length)}';
    }
    if (path.startsWith('/builder/ex/runtime/')) {
      return 'ex/runtime/${path.substring('/builder/ex/runtime/'.length)}';
    }
    return null;
  }

  Future<void> _serveAsset(HttpResponse response, String asset) async {
    final reader = assetReader;
    if (reader == null) {
      response.statusCode = HttpStatus.serviceUnavailable;
      await response.close();
      return;
    }
    try {
      final bytes = await reader(asset);
      final contentType = switch (asset) {
        'install.html' => ContentType.html,
        'style.css' => ContentType('text', 'css', charset: 'utf-8'),
        _ => ContentType('text', 'javascript', charset: 'utf-8'),
      };
      response
        ..headers.contentType = contentType
        ..headers.contentLength = bytes.length
        ..add(bytes);
      await response.close();
    } on Exception catch (error, stackTrace) {
      stderr.writeln(
          'Failed to serve PS5 installer asset "$asset": $error\n$stackTrace');
      response.statusCode = HttpStatus.notFound;
      await response.close();
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff')
      ..set('Referrer-Policy', 'no-referrer');

    final path = request.uri.path;
    final completionRoute =
        RegExp(r'^/api/install/([A-F0-9]{10})/complete$').firstMatch(path);
    if (completionRoute != null) {
      if (request.method != 'POST') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'POST');
        await response.close();
        return;
      }
      final token = _downloadToken;
      if (!offlineBuildReady ||
          token == null ||
          completionRoute.group(1) != _installCode(token)) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      if (request.contentLength > 0) {
        response.statusCode = HttpStatus.badRequest;
        await response.close();
        return;
      }
      if (request.contentLength < 0) {
        await for (final chunk in request) {
          if (chunk.isNotEmpty) {
            response.statusCode = HttpStatus.badRequest;
            await response.close();
            return;
          }
        }
      }

      try {
        final releasedBytes = await cleanBuild(afterInstall: true);
        if (releasedBytes == null) {
          response.statusCode = HttpStatus.notFound;
          await response.close();
          return;
        }
        response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'releasedBytes': releasedBytes}));
      } on Exception {
        response.statusCode = HttpStatus.internalServerError;
      }
      await response.close();
      return;
    }

    final youtubePackagePath =
        _firmware == null ? null : _youtubePackagePath(_firmware!);
    final isPublishedYoutubePackage = youtubePackagePath != null &&
        path == youtubePackagePath &&
        offlineBuildReady &&
        !_verifyOnly;
    if (request.method != 'GET' &&
        !(request.method == 'HEAD' && isPublishedYoutubePackage)) {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(
        HttpHeaders.allowHeader,
        isPublishedYoutubePackage ? 'GET, HEAD' : 'GET',
      );
      await response.close();
      return;
    }

    final installCodeRoute =
        RegExp(r'^/api/install/([A-F0-9]{10})$').firstMatch(path);
    if (installCodeRoute != null) {
      final token = _downloadToken;
      if (!offlineBuildReady ||
          token == null ||
          installCodeRoute.group(1) != _installCode(token)) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({
        'firmware': _firmware,
        'channel': 'unified',
        'download': '/installers/$token.elf',
        'sha256': _installerSha256,
        'bytes': _installerFile!.lengthSync(),
        'verifyOnly': _verifyOnly,
        'payloads': _payloadNames,
      }));
      await response.close();
      return;
    }

    if (path == '/api/runtime') {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({
        'runtime': '/builder/runtime/runtime.js',
        'base': '/builder/runtime/',
      }));
      await response.close();
      return;
    }

    if (path == '/install' && offlineBuildReady) {
      await _serveAsset(response, 'install.html');
      return;
    }

    if (path == '/install.js' && offlineBuildReady) {
      await _serveAsset(response, 'install.js');
      return;
    }

    if (path == '/style.css' && offlineBuildReady) {
      await _serveAsset(response, 'style.css');
      return;
    }

    if (path == '/src/utils/rop_slave.js' && offlineBuildReady) {
      await _serveAsset(response, 'runtime/src/utils/rop_slave.js');
      return;
    }

    final offsetRoute =
        RegExp(r'^/offsets/(\d{1,2}\.\d{2})\.js$').firstMatch(path);
    if (offsetRoute != null &&
        offlineBuildReady &&
        offsetRoute.group(1) == _firmware) {
      await _serveAsset(response, 'runtime/offsets/${offsetRoute.group(1)}.js');
      return;
    }

    if (path == '/autoload.js' && offlineBuildReady) {
      await _serveAsset(response, 'autoload.js');
      return;
    }

    if (path == '/sha256.js' && offlineBuildReady) {
      await _serveAsset(response, 'sha256.js');
      return;
    }

    if (isPublishedYoutubePackage) {
      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      final proxy = youtubePackageProxy;
      if (proxy == null) {
        await _serveYoutubePackage(request, response, _firmware!);
      } else {
        await proxy(request, response, _firmware!);
      }
      return;
    }

    final runtimePath = _runtimeAssetPath(path);
    if (runtimePath != null && offlineBuildReady) {
      await _serveAsset(response, runtimePath);
      return;
    }

    final installerRoute =
        RegExp(r'^/installers/([a-f0-9]{48})\.elf$').firstMatch(path);
    if (installerRoute != null &&
        offlineBuildReady &&
        installerRoute.group(1) == _downloadToken) {
      await _serveFile(
          response, _installerFile!, 'Snipers-YouTube-Installer.elf');
      return;
    }

    if (path == '/api/status') {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode({
        'lanServer': true,
        'engineReady': _engineReady,
        'offlineBuildReady': offlineBuildReady,
        'imageUrl': offlineBuildReady
            ? '/builder/youtube-bundles/$_downloadToken.dat'
            : null,
        'installerUrl': offlineBuildReady ? '/builder/installer.elf' : null,
        'installPageUrl': offlineBuildReady
            ? '/install?code=${_installCode(_downloadToken!)}'
            : null,
        'installCode': offlineBuildReady ? _installCode(_downloadToken!) : null,
      }));
      await response.close();
      return;
    }

    if (path == '/builder/installer.elf' && offlineBuildReady) {
      await _serveFile(
          response, _installerFile!, 'Snipers-YouTube-Installer.elf');
      return;
    }

    final imageRoute = RegExp(r'^/builder/youtube-bundles/([a-f0-9]{48})\.dat$')
        .firstMatch(path);
    if (imageRoute != null &&
        offlineBuildReady &&
        imageRoute.group(1) == _downloadToken) {
      await _serveFile(response, _imageFile!, 'download0.dat');
      return;
    }

    if (path == '/' || path == '/index.html') {
      final userAgent =
          request.headers.value(HttpHeaders.userAgentHeader) ?? '';
      if (offlineBuildReady &&
          RegExp(r'PlayStation 5', caseSensitive: false).hasMatch(userAgent)) {
        response
          ..statusCode = HttpStatus.found
          ..headers.set(
            HttpHeaders.locationHeader,
            Uri(
              path: '/install',
              queryParameters: {'code': _installCode(_downloadToken!)},
            ).toString(),
          );
        await response.close();
        return;
      }
      response.headers.contentType = ContentType.html;
      response.write(_landingPage(
        engineReady: _engineReady,
        buildReady: offlineBuildReady,
        installPageUrl: offlineBuildReady
            ? '/install?code=${_installCode(_downloadToken!)}'
            : null,
      ));
      await response.close();
      return;
    }

    response.statusCode = HttpStatus.notFound;
    await response.close();
  }

  Future<void> _serveFile(
    HttpResponse response,
    File file,
    String downloadName,
  ) async {
    late int length;
    try {
      length = await file.length();
    } on IOException catch (error, stackTrace) {
      stderr.writeln('Failed to serve LAN build file: $error\n$stackTrace');
      response.statusCode = HttpStatus.internalServerError;
      await response.close();
      return;
    }

    response
      ..headers.contentType = ContentType('application', 'octet-stream')
      ..headers.contentLength = length
      ..headers.set(
        'content-disposition',
        'attachment; filename="$downloadName"',
      );
    try {
      await response.addStream(file.openRead());
      await response.close();
    } on IOException catch (error, stackTrace) {
      stderr.writeln('Failed to stream LAN build file: $error\n$stackTrace');
      try {
        await response.close();
      } on IOException catch (closeError, closeStackTrace) {
        stderr.writeln(
          'Failed to close LAN response: $closeError\n$closeStackTrace',
        );
      }
    }
  }

  static Future<List<InternetAddress>> _wifiAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    final addresses = <InternetAddress>[];

    for (final interface in interfaces) {
      final name = interface.name.toLowerCase();
      if (!name.startsWith('wlan') &&
          !name.startsWith('wifi') &&
          !name.startsWith('ap') &&
          !name.startsWith('swlan')) {
        continue;
      }
      for (final address in interface.addresses) {
        if (_isPrivateIpv4(address) &&
            !addresses.any((existing) => existing.address == address.address)) {
          addresses.add(address);
        }
      }
    }

    return addresses;
  }

  static bool _isPrivateIpv4(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }
}

String _landingPage({
  required bool engineReady,
  required bool buildReady,
  required String? installPageUrl,
}) =>
    '''
<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="referrer" content="no-referrer">
  <title>Snipers · Máy chủ LAN</title>
  <style>
    :root { color-scheme: dark; font: 16px system-ui, sans-serif; }
    body { margin: 0; padding: 2rem 1rem; background: #10120f; color: #f3f5ef; }
    main { max-width: 42rem; margin: auto; }
    h1 { color: #c5f86a; }
    section { margin-top: 1rem; padding: 1rem; border: 1px solid #454b40; border-radius: 1rem; }
    p { line-height: 1.55; }
    .muted { color: #c1c6b9; }
  </style>
</head>
<body>
  <main>
    <h1>Snipers · Máy chủ nội bộ</h1>
    <section>
      <strong>Đã kết nối tới máy chủ Android qua mạng LAN.</strong>
      <p class="muted">Máy chủ phản hồi bình thường.</p>
    </section>
    <section>
      <strong>Engine local: ${engineReady ? 'đã chuẩn bị' : 'chưa chuẩn bị'}</strong>
      <p class="muted">${buildReady ? 'Build đã hoàn tất; các file được cung cấp từ điện thoại.' : 'Chuẩn bị engine và chạy build trong ứng dụng Android.'}</p>
      ${buildReady ? '<p>Mã xác nhận PS5: <strong>${_escapeHtml(installPageUrl!.split('code=').last)}</strong></p><p><a href="$installPageUrl">Cài đặt tự động qua LAN</a></p><p class="muted">Mở trang cài đặt trên PS5, xác nhận cài đặt; installer sẽ tải và xác minh image qua LAN. Bản startup cũ được sao lưu trước khi thay thế.</p>' : ''}
      <p class="muted">Chỉ dùng trong mạng nội bộ đáng tin cậy. Chưa có kiểm thử phần cứng PS5.</p>
    </section>
  </main>
</body>
</html>
''';

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');
