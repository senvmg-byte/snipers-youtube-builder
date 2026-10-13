import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_brand.dart';
import 'local_builder_server.dart';
import 'local_engine_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SnipersBuilderApp());
}

class SnipersBuilderApp extends StatelessWidget {
  const SnipersBuilderApp({super.key});

  @override
  Widget build(BuildContext context) {
    const lime = Color(0xFFC5F86A);
    const background = Color(0xFF0D100D);
    const surface = Color(0xFF171C17);
    const outline = Color(0xFF2A332A);
    return MaterialApp(
      title: 'Snipers Builder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: lime,
          brightness: Brightness.dark,
        ).copyWith(
          primary: lime,
          onPrimary: const Color(0xFF151A12),
          secondary: const Color(0xFF9DE8B5),
          surface: surface,
          surfaceContainerHighest: const Color(0xFF202720),
          outline: outline,
        ),
        scaffoldBackgroundColor: background,
        cardColor: surface,
        dividerColor: outline,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          foregroundColor: Color(0xFFF3F5EF),
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 0,
          toolbarHeight: 72,
        ),
        cardTheme: CardThemeData(
          color: surface,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: outline),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111611),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: lime, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 50),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            side: const BorderSide(color: outline),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF263026),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      home: const BuilderHomePage(),
    );
  }
}

class BuilderHomePage extends StatelessWidget {
  const BuilderHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: 1,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 18,
          title: const Row(
            children: [
              SnipersBrandMark(size: 42),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'SNIPERS',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.1,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'YOUTUBE BUILDER',
                    style: TextStyle(
                      color: Color(0xFF9AA596),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          bottom: const TabBar(
            dividerColor: Color(0xFF252D25),
            indicatorSize: TabBarIndicatorSize.tab,
            indicatorPadding: EdgeInsets.symmetric(horizontal: 12),
            labelStyle: TextStyle(fontWeight: FontWeight.w700),
            unselectedLabelColor: Color(0xFF899187),
            tabs: [
              Tab(icon: Icon(Icons.wifi_tethering), text: 'LAN / OFFLINE'),
              Tab(icon: Icon(Icons.cloud_outlined), text: 'ONLINE BUILDER'),
            ],
          ),
        ),
        body: const TabBarView(
          physics: NeverScrollableScrollPhysics(),
          children: [
            LocalServerPage(),
            HostedBuilderPage(),
          ],
        ),
      ),
    );
  }
}

class LocalServerPage extends StatefulWidget {
  const LocalServerPage({super.key});

  @override
  State<LocalServerPage> createState() => _LocalServerPageState();
}

class _LocalServerPageState extends State<LocalServerPage> {
  final LocalEngineService _engine = LocalEngineService();
  final ValueNotifier<String> _progressNotifier = ValueNotifier('');
  late final LocalBuilderServer _server;
  final List<LocalPayload> _payloads = [];
  StreamSubscription<String>? _progressSubscription;
  EngineManifest? _manifest;
  LocalBuildResult? _buildResult;
  UpstreamSourceRelease? _upstreamRelease;
  List<String> _supportedFirmwares = const [];
  String? _selectedFirmware;
  String? _engineError;
  String get _progress => _progressNotifier.value;
  set _progress(String value) => _progressNotifier.value = value;
  bool _loadingEngine = true;
  bool _engineReady = false;
  bool _preparing = false;
  bool _checkingSource = false;
  bool _updatingSource = false;
  bool _selecting = false;
  bool _building = false;
  bool _starting = false;
  bool _cleaning = false;

  @override
  void initState() {
    super.initState();
    _server = LocalBuilderServer(
      assetReader: _engine.readInstallerAsset,
      onBuildCleaned: (afterInstall) async {
        if (!mounted) return;
        setState(() {
          _buildResult = null;
          _progress = afterInstall
              ? 'PS5 đã xác nhận cài đặt; cache và file build tạm đã được xóa.'
              : 'Đã xóa image và file build tạm; payload đã nhập vẫn được giữ.';
        });
      },
    );
    _progressSubscription = _engine.progress.listen(
      (message) {
        if (mounted && message.isNotEmpty) _progress = message;
      },
      onError: (Object error) {
        if (mounted) _showMessage('Không nhận được tiến độ build: $error');
      },
    );
    unawaited(_refreshEngine());
  }

  @override
  void dispose() {
    unawaited(_progressSubscription?.cancel());
    unawaited(_server.stop());
    _progressNotifier.dispose();
    super.dispose();
  }

  Future<void> _refreshEngine() async {
    try {
      final manifest = await EngineManifest.load();
      final installed = await _engine.isInstalled(manifest);
      final firmwares =
          installed ? await _engine.supportedFirmwares() : manifest.firmware;
      if (!mounted) return;
      _server.setEngineReady(installed);
      setState(() {
        _manifest = manifest;
        _engineReady = installed;
        _supportedFirmwares = firmwares;
        _selectedFirmware = firmwares.contains(_selectedFirmware)
            ? _selectedFirmware
            : firmwares.contains('13.60')
                ? '13.60'
                : firmwares.first;
        _engineError = null;
        _loadingEngine = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _engineError = error.toString();
        _loadingEngine = false;
      });
    }
  }

  Future<void> _prepareEngine() async {
    final manifest = _manifest;
    if (manifest == null || _preparing) return;
    setState(() {
      _preparing = true;
      _progress = 'Đang xác minh gói engine tích hợp trong APK.';
    });
    try {
      await _engine.prepare(manifest);
      final installed = await _engine.isInstalled(manifest);
      if (!installed) {
        throw StateError(
            'Engine giải nén xong nhưng kiểm tra cài đặt không thành công.');
      }
      final firmwares = await _engine.supportedFirmwares();
      _server.setEngineReady(true);
      if (mounted) {
        setState(() {
          _engineReady = true;
          _supportedFirmwares = firmwares;
          _selectedFirmware = firmwares.contains(_selectedFirmware)
              ? _selectedFirmware
              : firmwares.contains('13.60')
                  ? '13.60'
                  : firmwares.first;
          _engineError = null;
          _progress = 'Engine ${manifest.version} đã cài và xác minh.';
        });
      }
      _showMessage('Đã chuẩn bị engine local ${manifest.version}.');
    } catch (error) {
      if (mounted) {
        setState(() {
          _engineError = error.toString();
          _progress = 'Chuẩn bị engine thất bại.';
        });
      }
      _showMessage('Không thể chuẩn bị engine: $error');
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _checkUpstreamSource() async {
    final manifest = _manifest;
    if (manifest == null || _checkingSource || _updatingSource) return;
    setState(() => _checkingSource = true);
    try {
      final release = await _engine.checkUpstreamSource(manifest);
      if (!mounted) return;
      setState(() => _upstreamRelease = release);
      _showMessage(release.updateAvailable
          ? 'Có source GitHub mới: ${release.latestTag}.'
          : 'Source engine đang ở phiên bản mới nhất (${release.latestTag}).');
    } catch (error) {
      _showMessage('Không kiểm tra được source GitHub: $error');
    } finally {
      if (mounted) setState(() => _checkingSource = false);
    }
  }

  Future<void> _updateUpstreamSource() async {
    final manifest = _manifest;
    final release = _upstreamRelease;
    if (manifest == null ||
        release == null ||
        !release.updateAvailable ||
        _updatingSource) {
      return;
    }
    setState(() {
      _updatingSource = true;
      _progress = 'Đang tải và xác minh source GitHub ${release.latestTag}.';
    });
    try {
      final installed =
          await _engine.updateUpstreamSource(manifest, release.latestTag);
      final firmwares = await _engine.supportedFirmwares();
      if (!mounted) return;
      setState(() {
        _upstreamRelease = installed;
        _supportedFirmwares = firmwares;
        if (!firmwares.contains(_selectedFirmware)) {
          _selectedFirmware =
              firmwares.contains('13.60') ? '13.60' : firmwares.first;
        }
        _progress =
            'Đã cập nhật source và danh sách firmware ${installed.latestTag}.';
        _buildResult = null;
        _server.clearBuild();
      });
      _showMessage(
          'Đã cập nhật source GitHub ${installed.latestTag} và xác minh SHA-256.');
    } catch (error) {
      _showMessage('Cập nhật source GitHub thất bại: $error');
    } finally {
      if (mounted) setState(() => _updatingSource = false);
    }
  }

  Future<void> _selectPayloads() async {
    if (_selecting || _building) return;
    setState(() => _selecting = true);
    try {
      final selected = await _engine.selectPayloads();
      if (selected.isNotEmpty && mounted) {
        setState(() {
          _payloads
            ..clear()
            ..addAll(selected);
          _buildResult = null;
          _server.clearBuild();
        });
      }
    } catch (error) {
      _showMessage('Không thể thêm payload: $error');
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  void _removePayload(LocalPayload payload) {
    setState(() {
      _payloads.remove(payload);
      _buildResult = null;
      _server.clearBuild();
    });
  }

  void _movePayload(int index, int offset) {
    final destination = index + offset;
    if (destination < 0 || destination >= _payloads.length) return;
    setState(() {
      final payload = _payloads.removeAt(index);
      _payloads.insert(destination, payload);
      _buildResult = null;
      _server.clearBuild();
    });
  }

  Future<void> _buildLocal() async {
    final manifest = _manifest;
    final firmware = _selectedFirmware;
    if (manifest == null ||
        firmware == null ||
        !_engineReady ||
        _payloads.isEmpty ||
        _building) {
      return;
    }
    setState(() {
      _building = true;
      _buildResult = null;
      _progress = 'Đang chuẩn bị build local...';
    });
    try {
      if (!_server.isRunning) await _server.start();
      if (!mounted) return;
      setState(() {});
      final address = _server.urls.first.host;
      final result = await _engine.build(
        manifest: manifest,
        firmware: firmware,
        address: address,
        payloads: List<LocalPayload>.unmodifiable(_payloads),
      );
      _server.publishBuild(
        downloadToken: result.downloadToken,
        imagePath: result.imagePath,
        installerPath: result.installerPath,
        firmware: result.firmware,
        installerSha256: result.installerSha256,
        payloadNames: List<String>.unmodifiable(
          _payloads.map((payload) => payload.name),
        ),
        verifyOnly: result.verifyOnly,
      );
      if (mounted) {
        setState(() {
          _buildResult = result;
          _progress = 'Build xong; SHA-256 image ${result.imageSha256}.';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _progress = 'Build local thất bại.');
      _showMessage('Build local không thành công: $error');
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Future<void> _confirmAndCleanBuild() async {
    if (_cleaning || _building || _buildResult == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa cache của build này?'),
        content: const Text(
          'Image PS5, installer và các file trung gian của build này sẽ bị xóa. '
          'Engine và payload đã nhập sẽ được giữ lại. Muốn cài lên PS5 sau đó '
          'thì cần build image lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa cache'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _cleaning = true);
    try {
      final releasedBytes = await _server.cleanBuild();
      if (releasedBytes == null) {
        _showMessage('Không tìm thấy build để dọn.');
        return;
      }
      _showMessage('Đã xóa ${_formatBytes(releasedBytes)} file build tạm.');
    } catch (error) {
      _showMessage('Không thể xóa file build tạm: $error');
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  Future<void> _toggleServer() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      if (_server.isRunning) {
        await _server.stop();
      } else {
        await _server.start();
      }
    } catch (error) {
      _showMessage('Không thể khởi động máy chủ: $error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _copyUrl(Uri url) async {
    await _copyText(url.toString());
  }

  Future<void> _copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showMessage('Đã sao chép vào clipboard.');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final running = _server.isRunning;
    final manifest = _manifest;
    final result = _buildResult;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF253321), Color(0xFF151B15), Color(0xFF121612)],
            ),
            border: Border.all(color: const Color(0xFF394B34)),
          ),
          child: const Row(
            children: [
              SnipersBrandMark(size: 58),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LOCAL WORKSPACE',
                      style: TextStyle(
                        color: Color(0xFFC5F86A),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.8,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'PS5 Payload Studio',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Build offline · verify · install over LAN',
                      style: TextStyle(
                        color: Color(0xFFADB7A7),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _loadingEngine
                      ? 'Đang kiểm tra engine local...'
                      : _engineReady
                          ? 'Engine Android đã sẵn sàng'
                          : 'Chưa chuẩn bị engine local',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  manifest == null
                      ? _engineError ?? 'Không đọc được manifest engine.'
                      : 'Engine ${manifest.version} · gói ${_formatBytes(manifest.bytes)} · cần khoảng ${_formatBytes(manifest.uncompressedBytes * 2 + manifest.bytes)} dung lượng trống.',
                ),
                if (manifest != null) ...[
                  const SizedBox(height: 8),
                  SelectableText('SHA-256: ${manifest.sha256}'),
                ],
                if (_engineError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _engineError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loadingEngine || _preparing || _engineReady
                      ? null
                      : _prepareEngine,
                  icon: _preparing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_user_outlined),
                  label: Text(_preparing
                      ? 'Đang xác minh và cài...'
                      : _engineReady
                          ? 'Engine đã cài'
                          : 'Cài engine từ APK'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nguồn chính thức GitHub',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(
                  _upstreamRelease == null
                      ? 'Kiểm tra release source của GronedWaffel/snipers-youtube-builder khi có Internet.'
                      : 'Đang dùng ${_upstreamRelease!.currentTag}; GitHub mới nhất ${_upstreamRelease!.latestTag}. '
                          '${_upstreamRelease!.updateAvailable ? "Có thể cập nhật source firmware." : "Không có bản mới hơn."}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Source ZIP được đối chiếu SHA-256 với GitHub trước khi cài dữ liệu firmware. '
                  'Cập nhật này không thay APK hoặc native runtime; các thay đổi mã Android cần cài APK mới.',
                ),
                if (_upstreamRelease != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    'Source SHA-256: ${_upstreamRelease!.sourceSha256}',
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: manifest == null ||
                              _checkingSource ||
                              _updatingSource ||
                              _building
                          ? null
                          : _checkUpstreamSource,
                      icon: _checkingSource
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_checkingSource
                          ? 'Đang kiểm tra...'
                          : 'Kiểm tra cập nhật'),
                    ),
                    if (_upstreamRelease?.updateAvailable ?? false)
                      FilledButton.icon(
                        onPressed: !_engineReady || _updatingSource || _building
                            ? null
                            : _updateUpstreamSource,
                        icon: _updatingSource
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.system_update_alt),
                        label: Text(_updatingSource
                            ? 'Đang tải và xác minh...'
                            : 'Cập nhật source'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Payload cho firmware ${_selectedFirmware ?? "—"}',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _supportedFirmwares.contains(_selectedFirmware)
                      ? _selectedFirmware
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Firmware PS5',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final firmware in _supportedFirmwares)
                      DropdownMenuItem(
                        value: firmware,
                        child: Text(firmware),
                      ),
                  ],
                  onChanged: !_engineReady || _building
                      ? null
                      : (firmware) {
                          if (firmware == null) return;
                          setState(() {
                            _selectedFirmware = firmware;
                            _buildResult = null;
                            _server.clearBuild();
                          });
                        },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Chọn tối đa 8 file ELF/BIN (64 MiB mỗi file, 128 MiB tổng). '
                  'Thứ tự trong danh sách là thứ tự chạy. App kiểm tra cấu trúc '
                  'ELF x86-64 và SHA-256; định dạng hợp lệ không bảo đảm tương '
                  'thích firmware.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _selecting || _building ? null : _selectPayloads,
                  icon: _selecting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(
                      _selecting ? 'Đang nhập file...' : 'Chọn file ELF/BIN'),
                ),
                if (_payloads.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Chưa chọn payload nào.'),
                  ),
                ..._payloads.asMap().entries.map((entry) {
                  final index = entry.key;
                  final payload = entry.value;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(payload.name),
                    subtitle: Text(
                      '${_formatBytes(payload.bytes)} · SHA-256 ${payload.sha256.substring(0, 12)}…',
                    ),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          tooltip: 'Chuyển lên',
                          onPressed: _building || index == 0
                              ? null
                              : () => _movePayload(index, -1),
                          icon: const Icon(Icons.arrow_upward),
                        ),
                        IconButton(
                          tooltip: 'Chuyển xuống',
                          onPressed: _building || index == _payloads.length - 1
                              ? null
                              : () => _movePayload(index, 1),
                          icon: const Icon(Icons.arrow_downward),
                        ),
                        IconButton(
                          tooltip: 'Gỡ payload',
                          onPressed:
                              _building ? null : () => _removePayload(payload),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Build offline trên Android',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'Engine chạy trong sandbox của ứng dụng; sau khi cài có thể '
                  'build không cần Termux hoặc Internet. Cần cùng Wi-Fi khi '
                  'PS5 tải các file từ máy chủ LAN.',
                ),
                ValueListenableBuilder<String>(
                  valueListenable: _progressNotifier,
                  builder: (context, _, __) {
                    if (!_building && _progress.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_building) ...[
                            const LinearProgressIndicator(),
                            const SizedBox(height: 8),
                          ],
                          _building
                              ? Text(_progress)
                              : SelectableText(_progress),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: !_engineReady ||
                          _payloads.isEmpty ||
                          _building ||
                          _loadingEngine
                      ? null
                      : _buildLocal,
                  icon: _building
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.build_outlined),
                  label:
                      Text(_building ? 'Đang build...' : 'Build image local'),
                ),
                if (result != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    'Image: ${_formatBytes(result.imageBytes)} · SHA-256 ${result.imageSha256}',
                  ),
                  SelectableText(
                      'Installer SHA-256: ${result.installerSha256}'),
                  const SizedBox(height: 8),
                  Text(
                    result.verifyOnly
                        ? 'Installer hiện chỉ xác minh, không thay thế startup YouTube.'
                        : 'Trên PS5, mở trang LAN bên dưới và xác nhận cài đặt. '
                            'Installer tự tải image qua LAN, kiểm tra hash, sao lưu '
                            'startup cũ rồi cài; không cần tải hoặc chép download0.dat.',
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Mã xác nhận PS5: '),
                      SelectableText(
                        result.downloadToken.substring(0, 10).toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xFFC5F86A),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sao chép mã xác nhận',
                        onPressed: () => _copyText(
                          result.downloadToken.substring(0, 10).toUpperCase(),
                        ),
                        icon: const Icon(Icons.copy),
                      ),
                    ],
                  ),
                  for (final url in _server.urls)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title:
                          const Text('Mở trang cài tự động trên PS5 cùng LAN'),
                      subtitle: SelectableText(
                        url.replace(
                          path: '/install',
                          queryParameters: {
                            'code': result.downloadToken
                                .substring(0, 10)
                                .toUpperCase(),
                          },
                        ).toString(),
                      ),
                      trailing: IconButton(
                        tooltip: 'Sao chép liên kết cài đặt PS5',
                        onPressed: () => _copyUrl(
                          url.replace(
                            path: '/install',
                            queryParameters: {
                              'code': result.downloadToken
                                  .substring(0, 10)
                                  .toUpperCase(),
                            },
                          ),
                        ),
                        icon: const Icon(Icons.copy),
                      ),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _building || _cleaning ? null : _confirmAndCleanBuild,
                    icon: _cleaning
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_sweep_outlined),
                    label: Text(
                      _cleaning
                          ? 'Đang xóa cache...'
                          : 'Xóa cache build thủ công',
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Xóa image, installer và file build tạm; giữ engine và payload đã nhập.',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      running ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                      color: running
                          ? const Color(0xFFC5F86A)
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        running
                            ? 'Máy chủ LAN đang chạy'
                            : 'Máy chủ LAN đang tắt',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _starting ? null : _toggleServer,
                  icon: Icon(running ? Icons.stop : Icons.play_arrow),
                  label: Text(
                    _starting
                        ? 'Đang xử lý…'
                        : running
                            ? 'Dừng máy chủ'
                            : 'Khởi động máy chủ LAN',
                  ),
                ),
              ],
            ),
          ),
        ),
        if (running) ...[
          const SizedBox(height: 8),
          Text('Mở một trong các địa chỉ này trên PS5:',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final url in _server.urls)
            Card(
              child: ListTile(
                leading: const Icon(Icons.language),
                title: SelectableText(url.toString()),
                trailing: IconButton(
                  tooltip: 'Sao chép địa chỉ',
                  onPressed: () => _copyUrl(url),
                  icon: const Icon(Icons.copy),
                ),
              ),
            ),
        ],
        const _InfoCard(
          title: 'Để PS5 truy cập được',
          body: 'Kết nối PS5 và Pixel vào cùng mạng Wi-Fi. Giữ app này đang mở '
              'ở màn hình máy chủ. Địa chỉ chỉ lắng nghe trên giao diện Wi-Fi '
              'IPv4 riêng; máy chủ sẽ dừng khi rời màn hình này.',
          icon: Icons.router_outlined,
        ),
      ],
    );
  }

  String _formatBytes(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFFC5F86A)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(body),
          ],
        ),
      ),
    );
  }
}

class HostedBuilderPage extends StatefulWidget {
  const HostedBuilderPage({super.key});

  @override
  State<HostedBuilderPage> createState() => _HostedBuilderPageState();
}

class _HostedBuilderPageState extends State<HostedBuilderPage> {
  static const _builderHost = 'sniperscheats.lol';
  static final _builderUrl = WebUri('https://sniperscheats.lol/builder/');

  InAppWebViewController? _webViewController;
  int _progress = 0;

  bool _isBuilderUrl(Uri uri) =>
      uri.scheme == 'https' && uri.host.toLowerCase() == _builderHost;

  Future<void> _openExternal(Uri uri, {required bool isDownload}) async {
    if (!_isBuilderUrl(uri)) {
      _showMessage('Đã chặn liên kết nằm ngoài trang builder đáng tin cậy.');
      return;
    }
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      _showMessage(
        isDownload
            ? 'Không thể mở file tải xuống trong trình duyệt.'
            : 'Không tìm thấy trình duyệt để mở liên kết này.',
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _handleBack() async {
    final controller = _webViewController;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _handleBack() && mounted) {
          await SystemNavigator.pop();
        }
      },
      child: Column(
        children: [
          if (_progress < 100)
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress / 100,
              color: const Color(0xFFC5F86A),
              backgroundColor: const Color(0xFF30362B),
            ),
          Expanded(
            child: InAppWebView(
              gestureRecognizers: const {
                Factory<OneSequenceGestureRecognizer>(
                  VerticalDragGestureRecognizer.new,
                ),
              },
              initialUrlRequest: URLRequest(url: _builderUrl),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                disableVerticalScroll: false,
                verticalScrollBarEnabled: true,
                useShouldOverrideUrlLoading: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: false,
                supportMultipleWindows: false,
                safeBrowsingEnabled: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onProgressChanged: (_, progress) {
                if (mounted) setState(() => _progress = progress);
              },
              shouldOverrideUrlLoading: (_, action) async {
                final webUri = action.request.url;
                if (webUri == null) return NavigationActionPolicy.CANCEL;
                final uri = Uri.tryParse(webUri.toString());
                if (uri == null) return NavigationActionPolicy.CANCEL;
                if (_isBuilderUrl(uri)) return NavigationActionPolicy.ALLOW;
                if (uri.scheme == 'https') {
                  await _openExternal(uri, isDownload: false);
                }
                return NavigationActionPolicy.CANCEL;
              },
              onDownloadStartRequest: (_, request) async {
                final uri = Uri.tryParse(request.url.toString());
                if (uri != null) {
                  await _openExternal(uri, isDownload: true);
                } else {
                  _showMessage('Đường dẫn tải xuống không hợp lệ.');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
