import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import 'log.dart';
import 'services/dns_probe.dart';
import 'services/installed_apps.dart';
import 'services/latency.dart';
import 'services/tunnel_probe.dart';
import 'services/server_source.dart';
import 'services/update_service.dart';
import 'services/xray_config.dart';

enum TunnelState { disconnected, connecting, connected, disconnecting }

class _Attempt {
  const _Attempt(
    this.node,
    this.host,
    this.mode, {
    this.sni = false,
    this.dns = 'direct',
    this.insecure = false,
  });

  final ServerNode node;
  final String host;
  final String mode;
  final bool sni;
  final String dns;
  final bool insecure;

  _Attempt copyWith({String? mode, String? dns, bool? insecure}) {
    return _Attempt(
      node,
      host,
      mode ?? this.mode,
      sni: sni,
      dns: dns ?? this.dns,
      insecure: insecure ?? this.insecure,
    );
  }
}

enum _ConnectOutcome { connected, failed, tunnelFailed }

class AppState extends ChangeNotifier {
  static const _kBugHost = 'bug_host';
  static const _kBugHostSni = 'bug_host_sni';
  static const _kDnsMode = 'dns_mode';
  static const _kDnsServer = 'dns_server';
  static const _kDnsSuccess = 'dns_success';
  static const _kAllowInsecure = 'allow_insecure';
  static const _kGameMode = 'game_mode';
  static const _kAllowedApps = 'allowed_apps';
  static const _kSources = 'sources';
  static const _kAutoSelect = 'auto_select';
  static const _kAutoUpdate = 'auto_update';
  static const _kSelected = 'selected_raw';
  static const _kCache = 'server_cache';

  final ServerSource _serverSource = ServerSource();
  late SharedPreferences _prefs;

  final List<LogEntry> logs = [];
  static const int _maxLogs = 800;

  String bugHost = '';
  bool bugHostSni = false;
  String dnsMode = 'direct';
  String dnsServer = 'auto';
  bool allowInsecure = false;
  bool gameMode = false;
  List<String> allowedApps = const [
    'com.roblox.client',
    'com.tencent.ig',
    'com.levelinfinite.gst',
    'com.supercell.clashofclans',
  ];
  List<String> sources = List<String>.from(ServerSource.defaults);
  bool autoSelect = true;
  bool autoUpdate = true;
  List<ServerNode> servers = [];
  ServerNode? selected;
  bool loadingServers = false;
  String? serversError;
  String? lastError;
  String? notice;
  TunnelState tunnel = TunnelState.disconnected;
  V2RayStatus? traffic;
  DateTime? connectedSince;
  bool busy = false;
  String appVersion = '1.0.0';
  String appBuild = '1';
  bool checkingUpdate = false;
  int _disconnectSignals = 0;
  ReleaseInfo? update;
  bool updatePromptPending = false;

  final Map<String, String> _dnsSuccess = {};

  FlutterV2ray? _core;
  bool _coreReady = false;
  bool _disposed = false;
  Timer? _ticker;
  Timer? _startupUpdate;

  bool get isAndroid => Platform.isAndroid;
  bool get isConnected => tunnel == TunnelState.connected;

  /// Resolver yang dipakai Xray dan DNS probe.
  List<String> get dnsServers {
    switch (dnsServer) {
      case 'cloudflare':
        return const ['1.1.1.1'];
      case 'google':
        return const ['8.8.8.8'];
      default:
        return const ['8.8.8.8', '1.1.1.1'];
    }
  }

  String get dnsServerLabel {
    switch (dnsServer) {
      case 'cloudflare':
        return 'Cloudflare (1.1.1.1)';
      case 'google':
        return 'Google (8.8.8.8)';
      default:
        return 'Otomatis (8.8.8.8 + 1.1.1.1)';
    }
  }

  /// Mode DNS yang pernah berhasil untuk server ini, jika ada.
  String _dnsModeFor(ServerNode node) => _dnsSuccess[node.raw] ?? dnsMode;

  String get statusLabel {
    switch (tunnel) {
      case TunnelState.connected:
        return 'Terhubung';
      case TunnelState.connecting:
        return 'Menghubungkan';
      case TunnelState.disconnecting:
        return 'Memutuskan';
      case TunnelState.disconnected:
        return 'Terputus';
    }
  }

  Duration get connectedDuration {
    final since = connectedSince;
    if (since == null) return Duration.zero;
    return DateTime.now().difference(since);
  }

  void addLog(LogLevel level, String message) {
    logs.add(LogEntry(time: DateTime.now(), level: level, message: message));
    if (logs.length > _maxLogs) {
      logs.removeRange(0, logs.length - _maxLogs);
    }
    _notify();
  }

  void clearLogs() {
    logs.clear();
    _notify();
  }

  String exportLogs() {
    final buffer = StringBuffer()
      ..writeln('BugTunnel $appVersion ($appBuild)')
      ..writeln('Android: ${Platform.operatingSystemVersion}')
      ..writeln('Bug host: ${bugHost.isEmpty ? 'tidak diisi' : bugHost}')
      ..writeln('Ganti SNI: ${bugHostSni ? 'ya' : 'tidak'}')
      ..writeln('Mode DNS: $dnsMode (resolver: $dnsServerLabel)')
      ..writeln(
        'Mode Game: ${gameMode ? 'aktif (${allowedApps.length} aplikasi diizinkan)' : 'nonaktif'}',
      )
      ..writeln('Sumber server: ${sources.length}')
      ..writeln('Server terpilih: ${selected?.name ?? '-'}')
      ..writeln('----------------------------------------');
    for (final entry in logs) {
      buffer.writeln(entry.toLine());
    }
    return buffer.toString();
  }

  Future<void> captureSystemLog() async {
    if (!Platform.isAndroid) {
      addLog(LogLevel.info, 'Log sistem hanya tersedia di Android.');
      return;
    }
    addLog(LogLevel.info, 'Membaca log sistem (logcat)...');
    try {
      final result = await Process.run('/system/bin/logcat', [
        '-d',
        '-v',
        'time',
        '-t',
        '500',
      ]).timeout(const Duration(seconds: 6));
      final text = '${result.stdout}';
      const noise = [
        'apkassets',
        'bufferqueueproducer',
        'nativeloader',
        'imetacker',
        'profileinstaller',
        'vulkan',
      ];
      final lines = text
          .split('\n')
          .where((line) {
            final lower = line.toLowerCase();
            if (noise.any((word) => lower.contains(word))) return false;
            return lower.contains('v2ray') ||
                lower.contains('xray') ||
                lower.contains('tun2socks') ||
                lower.contains('vpn_service') ||
                lower.contains('aarwi.bugtunnel');
          })
          .take(150)
          .toList();

      if (lines.isEmpty) {
        addLog(LogLevel.warning, 'Log sistem: tidak ada baris terkait Xray.');
        return;
      }
      addLog(LogLevel.info, '--- Log sistem (${lines.length} baris) ---');
      for (final line in lines) {
        final trimmed = line.trim();
        addLog(
          LogLevel.info,
          trimmed.length > 300 ? trimmed.substring(0, 300) : trimmed,
        );
      }
    } catch (error) {
      addLog(LogLevel.warning, 'Log sistem tidak bisa dibaca: $error');
    }
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    bugHost = _prefs.getString(_kBugHost) ?? '';
    bugHostSni = _prefs.getBool(_kBugHostSni) ?? false;
    dnsMode = _prefs.getString(_kDnsMode) == 'proxy' ? 'proxy' : 'direct';
    final storedDnsServer = _prefs.getString(_kDnsServer);
    dnsServer = storedDnsServer == 'google' || storedDnsServer == 'cloudflare'
        ? storedDnsServer!
        : 'auto';
    allowInsecure = _prefs.getBool(_kAllowInsecure) ?? false;
    gameMode = _prefs.getBool(_kGameMode) ?? false;
    final storedApps = _prefs.getStringList(_kAllowedApps);
    if (storedApps != null) allowedApps = storedApps;
    final storedDnsSuccess = _prefs.getString(_kDnsSuccess);
    if (storedDnsSuccess != null) {
      try {
        final decoded = jsonDecode(storedDnsSuccess);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            if (entry.key is String && entry.value is String) {
              _dnsSuccess[entry.key] = entry.value;
            }
          }
        }
      } catch (_) {
        // Abaikan cache DNS yang rusak.
      }
    }
    autoSelect = _prefs.getBool(_kAutoSelect) ?? true;
    autoUpdate = _prefs.getBool(_kAutoUpdate) ?? true;

    final storedSources = _prefs.getStringList(_kSources);
    if (storedSources != null && storedSources.isNotEmpty) {
      final cleaned = _extractUrls(storedSources);
      sources = cleaned.isEmpty
          ? List<String>.from(ServerSource.defaults)
          : cleaned;
      if (cleaned.length != storedSources.length) {
        await _prefs.setStringList(_kSources, sources);
      }
    }

    _restoreCache();

    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
      appBuild = info.buildNumber;
    } catch (_) {
      // Versi tetap memakai nilai bawaan bila platform tidak mendukung.
    }

    addLog(LogLevel.info, 'BugTunnel $appVersion ($appBuild) dimulai');
    addLog(
      LogLevel.info,
      'Bug host: ${bugHost.isEmpty ? 'tidak diisi' : bugHost}',
    );
    addLog(
      LogLevel.info,
      'Bug host sebagai SNI: ${bugHostSni ? 'ya' : 'tidak'}, '
      'DNS: $dnsMode ($dnsServerLabel), '
      'TLS insecure: ${allowInsecure ? 'ya' : 'tidak'}',
    );
    if (gameMode) {
      addLog(
        LogLevel.info,
        'Mode Game aktif: ${allowedApps.length} aplikasi diizinkan',
      );
    }
    addLog(LogLevel.info, 'Sumber server: ${sources.length}');

    await _initCore();
    _notify();

    if (autoUpdate) {
      _startupUpdate = Timer(const Duration(seconds: 4), () {
        checkForUpdate(silent: true);
      });
    }
  }

  void _restoreCache() {
    final raw = _prefs.getString(_kCache);
    if (raw != null) {
      try {
        final data = jsonDecode(raw);
        if (data is List) {
          servers = data
              .whereType<Map>()
              .map(
                (item) => ServerNode.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((node) => node.raw.isNotEmpty && node.address.isNotEmpty)
              .toList();
        }
      } catch (_) {
        // Cache rusak: mulai dari daftar kosong.
      }
    }

    final selectedRaw = _prefs.getString(_kSelected);
    if (selectedRaw != null) {
      for (final node in servers) {
        if (node.raw == selectedRaw) {
          selected = node;
          break;
        }
      }
    }
    if (selected == null) {
      for (final node in servers) {
        if (node.alive) {
          selected = node;
          break;
        }
      }
    }
    if (selected == null && servers.isNotEmpty) selected = servers.first;
  }

  Future<void> _initCore() async {
    if (!Platform.isAndroid) return;
    try {
      _core = FlutterV2ray(onStatusChanged: _onStatus);
      await _core!.initializeV2Ray();
      _coreReady = true;
      addLog(LogLevel.success, 'Mesin Xray siap');
    } catch (error) {
      _coreReady = false;
      lastError = 'Mesin tunnel gagal disiapkan: $error';
      addLog(LogLevel.error, 'Mesin Xray gagal disiapkan: $error');
    }
  }

  void _onStatus(V2RayStatus status) {
    if (_disposed) return;
    traffic = status;
    final value = status.state.toUpperCase();
    final previous = tunnel;

    if (value.contains('DISCONNECT')) {
      _disconnectSignals++;
      if (tunnel != TunnelState.disconnecting) {
        tunnel = TunnelState.disconnected;
      }
      connectedSince = null;
      _stopTicker();
    } else if (value.contains('CONNECTING')) {
      tunnel = TunnelState.connecting;
    } else if (value.contains('CONNECTED')) {
      if (tunnel != TunnelState.connected) {
        tunnel = TunnelState.connected;
        connectedSince ??= DateTime.now();
        _startTicker();
      }
    }

    if (tunnel != previous) {
      final level = tunnel == TunnelState.connected
          ? LogLevel.success
          : tunnel == TunnelState.disconnected
          ? LogLevel.warning
          : LogLevel.info;
      addLog(level, 'Status core: ${status.state}');
    }
    _notify();
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (tunnel == TunnelState.connected) _notify();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> refreshServers() async {
    if (loadingServers) return;
    loadingServers = true;
    serversError = null;
    lastError = null;
    addLog(LogLevel.info, 'Memuat server dari ${sources.length} sumber...');
    final started = DateTime.now();
    _notify();

    try {
      final fetched = await _serverSource.fetchAll(
        sources,
        onSource: (url, count) {
          final level = count > 0 ? LogLevel.info : LogLevel.warning;
          addLog(level, 'Sumber ${_shortUrl(url)}: $count server');
        },
      );
      if (fetched.isEmpty) {
        serversError = 'Tidak ada server yang bisa dibaca. Periksa koneksi internet atau sumber server di Pengaturan.';
        addLog(LogLevel.error, serversError!);
        return;
      }
      final seconds = DateTime.now().difference(started).inSeconds;
      addLog(
        LogLevel.info,
        'Total ${fetched.length} server unik (${seconds}s), menguji ping...',
      );
      servers = await LatencyTester.rank(fetched);
      _autoPick();
      _persistCache();
      _logTopServers();
    } catch (error) {
      serversError = 'Gagal memuat server: $error';
      addLog(LogLevel.error, serversError!);
    } finally {
      loadingServers = false;
      _notify();
    }
  }

  Future<void> pingServers() async {
    if (loadingServers || servers.isEmpty) return;
    loadingServers = true;
    addLog(LogLevel.info, 'Menguji ulang ping ${servers.length} server...');
    _notify();
    try {
      servers = await LatencyTester.rank(servers, limit: 120);
      _autoPick();
      _persistCache();
      _logTopServers();
    } catch (error) {
      lastError = 'Gagal menguji server: $error';
      addLog(LogLevel.error, lastError!);
    } finally {
      loadingServers = false;
      _notify();
    }
  }

  void _logTopServers() {
    final alive = servers.where((node) => node.alive).toList();
    addLog(
      LogLevel.info,
      'Hasil ping: ${alive.length} aktif dari ${servers.length} server',
    );
    for (final node in servers.take(5)) {
      addLog(
        node.alive ? LogLevel.success : LogLevel.warning,
        'Ping ${node.name} (${node.endpoint}): '
        '${node.alive ? '${node.latencyMs} ms' : 'tidak merespons'}',
      );
    }
  }

  String _shortUrl(String url) {
    var value = url
        .replaceFirst('https://', '')
        .replaceFirst('http://', '')
        .replaceFirst('www.', '');
    if (value.length > 42) value = '${value.substring(0, 42)}...';
    return value;
  }

  /// Mengambil hanya URL http(s) dari teks yang mungkin berisi banyak baris.
  ///
  /// Pengguna kadang menempel seluruh isi langganan ke kolom sumber. Tanpa
  /// pembersihan, setiap baris seperti `Hostname: ...` dianggap sebagai URL.
  static List<String> _extractUrls(Iterable<String> input) {
    final pattern = RegExp("https?://[^\\s<>\"']+");
    final result = <String>[];
    final seen = <String>{};
    for (final line in input) {
      for (final match in pattern.allMatches(line)) {
        var url = match.group(0)!;
        while (url.endsWith(',') ||
            url.endsWith('.') ||
            url.endsWith(';') ||
            url.endsWith(')') ||
            url.endsWith(']')) {
          url = url.substring(0, url.length - 1);
        }
        final uri = Uri.tryParse(url);
        if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
          continue;
        }
        if (seen.add(url)) result.add(url);
      }
    }
    return result;
  }

  Future<void> testSelectedServer() async {
    final node = selected;
    if (node == null) {
      addLog(LogLevel.warning, 'Tes manual: belum ada server terpilih.');
      return;
    }
    if (tunnel == TunnelState.connected) {
      addLog(
        LogLevel.warning,
        'Tes manual: putuskan koneksi dulu sebelum menguji server.',
      );
      return;
    }
    if (!_coreReady) await _initCore();
    if (_core == null) {
      addLog(LogLevel.error, 'Tes manual: mesin Xray tidak siap.');
      return;
    }

    addLog(LogLevel.info, 'Tes manual server ${node.name}');
    final dns = _dnsModeFor(node);
    final useSni = bugHostSni && !XrayConfig.hasOwnSni(node);
    final withBug = await _probe(
      _Attempt(
        node,
        bugHost,
        bugHost.isEmpty
            ? 'bawaan'
            : useSni
            ? 'bug host (SNI)'
            : 'bug host (Host)',
        sni: useSni,
        dns: dns,
      ),
    );
    if (!withBug && bugHost.isNotEmpty) {
      addLog(LogLevel.info, 'Mencoba tes ulang tanpa bug host...');
      await _probe(_Attempt(node, '', 'tanpa bug host', dns: dns));
    }
  }

  void _autoPick() {
    if (servers.isEmpty) {
      selected = null;
      return;
    }
    if (!autoSelect && selected != null) {
      for (final node in servers) {
        if (node.id == selected!.id &&
            XrayConfig.validationError(node) == null) {
          selected = node;
          return;
        }
      }
    }
    for (final node in servers) {
      if (node.alive && XrayConfig.validationError(node) == null) {
        selected = node;
        return;
      }
    }
    for (final node in servers) {
      if (XrayConfig.validationError(node) == null) {
        selected = node;
        return;
      }
    }
    selected = servers.first;
  }

  Future<void> selectServer(ServerNode node) async {
    final wasConnected = tunnel == TunnelState.connected;
    selected = node;
    _prefs.setString(_kSelected, node.raw);
    _notify();

    if (wasConnected) {
      await disconnect();
      await connect();
    }
  }

  Future<void> toggleConnection() async {
    if (busy) return;
    if (tunnel == TunnelState.connected || tunnel == TunnelState.connecting) {
      await disconnect();
    } else {
      await connect();
    }
  }

  Future<void> connect() async {
    if (busy) return;
    lastError = null;
    notice = null;

    if (!Platform.isAndroid) {
      lastError = 'Tunnel hanya bisa dijalankan di Android.';
      _notify();
      return;
    }

    if (!_coreReady) await _initCore();
    if (!_coreReady || _core == null) {
      lastError ??= 'Mesin tunnel tidak siap. Coba buka ulang aplikasi.';
      _notify();
      return;
    }

    if (servers.isEmpty) await refreshServers();
    if (servers.isEmpty) {
      lastError = 'Belum ada server. Muat daftar server dulu.';
      _notify();
      return;
    }

    final candidates = _connectCandidates();
    if (candidates.isEmpty) {
      lastError = 'Tidak ada server yang bisa dipakai.';
      _notify();
      return;
    }

    busy = true;
    _notify();

    try {
      final granted = await _core!.requestPermission();
      addLog(
        granted ? LogLevel.success : LogLevel.error,
        granted ? 'Izin VPN diberikan' : 'Izin VPN ditolak',
      );
      if (!granted) {
        lastError = 'Izin VPN ditolak. Izinkan BugTunnel membuat koneksi VPN, lalu coba lagi.';
        return;
      }

      final attempts = _buildAttempts(candidates);
      addLog(
        LogLevel.info,
        '${attempts.length} percobaan disiapkan, resolver $dnsServerLabel',
      );

      // Mode Game meniru HTTP Injector: aplikasi di luar daftar tidak lewat
      // tunnel. Plugin menerima daftar aplikasi yang DIBLOKIR dari VPN,
      // sehingga kita membalik daftar "aplikasi yang diizinkan".
      final blockedApps = gameMode ? await _blockedApps() : null;

      final ordered = await _prioritize(attempts);
      for (final attempt in ordered) {
        final outcome = await _tryWithFallbacks(
          attempt,
          blockedApps: blockedApps,
        );
        if (outcome == _ConnectOutcome.connected) return;
      }
      lastError =
          'Semua server gagal terhubung. Coba muat ulang daftar server.';
      addLog(LogLevel.error, lastError!);
      await captureSystemLog();
    } catch (error) {
      lastError = 'Gagal menyambung: $error';
      addLog(LogLevel.error, lastError!);
    } finally {
      busy = false;
      notice = null;
      if (tunnel != TunnelState.connected) {
        tunnel = TunnelState.disconnected;
        connectedSince = null;
        _stopTicker();
      }
      _notify();
    }
  }

  List<_Attempt> _buildAttempts(List<ServerNode> candidates) {
    final attempts = <_Attempt>[];
    for (final node in candidates) {
      final dns = _dnsModeFor(node);

      // Host-only dulu: ini yang dipakai HTTP Injector dan paling aman.
      if (bugHost.isNotEmpty) {
        attempts.add(_Attempt(node, bugHost, 'bug host (Host)', dns: dns));
      }

      // SNI bug hanya masuk akal pada node yang belum punya SNI sendiri.
      // Memaksanya pada node TLS biasa sudah terbukti membuat Xray gagal.
      if (bugHost.isNotEmpty && bugHostSni && !XrayConfig.hasOwnSni(node)) {
        attempts.add(
          _Attempt(node, bugHost, 'bug host (SNI)', sni: true, dns: dns),
        );
      }

      attempts.add(
        _Attempt(
          node,
          '',
          bugHost.isEmpty ? 'bawaan' : 'tanpa bug host',
          dns: dns,
        ),
      );
      if (attempts.length >= 4) break;
    }
    return attempts;
  }

  List<ServerNode> _connectCandidates() {
    final usable = servers.where(
      (node) => XrayConfig.validationError(node) == null,
    );
    final alive = usable.where((node) => node.alive).toList();
    final pool = alive.isNotEmpty ? alive : usable.toList();
    final skipped = servers.length - usable.length;
    if (skipped > 0) {
      addLog(
        LogLevel.warning,
        '$skipped server dilewati karena konfigurasinya ditolak Xray',
      );
    }
    final ordered = <ServerNode>[];

    final current = selected;
    if (current != null) {
      for (final node in pool) {
        if (node.id == current.id) {
          ordered.add(node);
          break;
        }
      }
    }

    for (final node in pool) {
      if (ordered.length >= 3) break;
      if (!ordered.any((item) => item.id == node.id)) ordered.add(node);
    }
    return ordered;
  }

  /// Daftar aplikasi yang TIDAK boleh lewat tunnel saat Mode Game aktif.
  ///
  /// `flutter_v2ray` memakai `blockedApps` (diblokir dari VPN), sedangkan UI
  /// BugTunnel menyimpan `allowedApps` (boleh lewat VPN). Karena itu daftar
  /// diambil dari semua aplikasi terpasang lalu dikurangi daftar yang diizinkan.
  Future<List<String>?> _blockedApps() async {
    final allowed = allowedApps
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (allowed.isEmpty) {
      addLog(
        LogLevel.warning,
        'Mode Game aktif tetapi daftar aplikasi kosong. Semua aplikasi lewat tunnel.',
      );
      return null;
    }
    if (!Platform.isAndroid) return null;

    try {
      final installed = await InstalledApps.load();
      final packages = installed
          .map((app) => app.packageName)
          .where((item) => item.isNotEmpty)
          .toSet();
      final blocked = packages.difference(allowed).toList()..sort();
      final missing = allowed.difference(packages).toList()..sort();

      if (missing.isNotEmpty) {
        addLog(
          LogLevel.warning,
          'Mode Game: ${missing.length} aplikasi diizinkan belum terpasang: '
          '${missing.take(6).join(', ')}'
          '${missing.length > 6 ? ' ...' : ''}',
        );
      }
      if (blocked.isEmpty) {
        addLog(
          LogLevel.warning,
          'Mode Game: tidak ada aplikasi lain untuk diblokir. Semua lewat tunnel.',
        );
        return null;
      }
      addLog(
        LogLevel.info,
        'Mode Game: ${allowed.length} aplikasi diizinkan, '
        '${blocked.length} aplikasi lain tidak lewat tunnel',
      );
      return blocked;
    } catch (error) {
      addLog(
        LogLevel.warning,
        'Mode Game: gagal membaca aplikasi terpasang ($error). '
        'Semua aplikasi lewat tunnel.',
      );
      return null;
    }
  }

  /// Menguji apakah server benar-benar bisa meneruskan trafik.
  ///
  /// Ping TCP hanya membuktikan port terbuka. Banyak server gratis menerima
  /// koneksi tetapi tidak bisa keluar ke internet. `getServerDelay` memakai
  /// core Xray untuk mengambil URL lewat server tersebut.
  Future<bool> _probe(_Attempt attempt) async {
    final core = _core;
    if (core == null) return false;
    addLog(LogLevel.info, 'Tes ${attempt.node.name} (${attempt.mode})...');
    final invalid = XrayConfig.validationError(attempt.node);
    if (invalid != null) {
      addLog(LogLevel.warning, 'Tes dilewati: $invalid');
      return false;
    }
    try {
      final config = XrayConfig.build(
        attempt.node,
        bugHost: attempt.host,
        overrideSni: attempt.sni,
        dnsMode: attempt.dns,
        dnsServers: dnsServers,
        allowInsecure: allowInsecure || attempt.insecure,
      );
      final delay = await core
          .getServerDelay(
            config: config,
            url: 'https://www.gstatic.com/generate_204',
          )
          .timeout(const Duration(seconds: 6), onTimeout: () => -1);
      if (delay > 0) {
        addLog(
          LogLevel.success,
          'Tes ${attempt.node.name} (${attempt.mode}) lolos: $delay ms',
        );
        return true;
      }
      addLog(
        LogLevel.warning,
        'Tes ${attempt.node.name} (${attempt.mode}) gagal: $delay',
      );
      return false;
    } catch (error) {
      addLog(
        LogLevel.warning,
        'Tes ${attempt.node.name} (${attempt.mode}) error: $error',
      );
      return false;
    }
  }

  /// Menaruh percobaan yang lolos tes nyata di depan.
  Future<List<_Attempt>> _prioritize(List<_Attempt> attempts) async {
    if (attempts.length <= 1) return attempts;

    final passed = <_Attempt>[];
    final failed = <_Attempt>[];
    for (final attempt in attempts.take(2)) {
      if (await _probe(attempt)) {
        passed.add(attempt);
      } else {
        failed.add(attempt);
      }
    }
    return [...passed, ...failed, ...attempts.skip(2)];
  }

  /// Mencoba kombinasi TLS insecure dan mode DNS bila tes tunnel gagal.
  ///
  /// Urutannya: insecure dengan DNS sama → DNS dibalik → keduanya. Bila core
  /// melaporkan server mati (`failed`), tidak ada gunanya mencoba kombinasi
  /// lain pada server yang sama.
  Future<_ConnectOutcome> _tryWithFallbacks(
    _Attempt attempt, {
    List<String>? blockedApps,
  }) async {
    var last = await _tryConnect(attempt, blockedApps: blockedApps);
    if (last == _ConnectOutcome.connected || last == _ConnectOutcome.failed) {
      return last;
    }

    final flipped = attempt.dns == 'proxy' ? 'direct' : 'proxy';
    final retries = <_Attempt>[
      if (!attempt.insecure)
        attempt.copyWith(
          mode: '${attempt.mode} • TLS insecure',
          insecure: true,
        ),
      attempt.copyWith(mode: '${attempt.mode} • DNS $flipped', dns: flipped),
      if (!attempt.insecure)
        attempt.copyWith(
          mode: '${attempt.mode} • TLS insecure • DNS $flipped',
          insecure: true,
          dns: flipped,
        ),
    ];

    for (final next in retries) {
      if (next.insecure && !attempt.insecure) {
        addLog(
          LogLevel.warning,
          'TLS insecure dicoba otomatis karena sertifikat server mungkin bermasalah.',
        );
      }
      addLog(LogLevel.info, 'Mencoba ulang dengan ${next.mode}...');
      last = await _tryConnect(next, blockedApps: blockedApps);
      if (last == _ConnectOutcome.connected || last == _ConnectOutcome.failed) {
        return last;
      }
    }
    return last;
  }

  Future<_ConnectOutcome> _tryConnect(
    _Attempt attempt, {
    List<String>? blockedApps,
  }) async {
    final node = attempt.node;
    selected = node;
    tunnel = TunnelState.connecting;
    notice = 'Mencoba ${node.name}...';
    addLog(LogLevel.info, 'Mencoba ${node.name} (${attempt.mode})');
    try {
      addLog(
        LogLevel.info,
        XrayConfig.describe(
          node,
          bugHost: attempt.host,
          overrideSni: attempt.sni,
          dnsMode: attempt.dns,
          dnsServers: dnsServers,
          allowInsecure: allowInsecure || attempt.insecure,
        ),
      );
    } catch (error) {
      addLog(LogLevel.warning, 'Ringkasan konfigurasi gagal: $error');
    }
    _notify();

    try {
      final config = XrayConfig.build(
        node,
        bugHost: attempt.host,
        overrideSni: attempt.sni,
        dnsMode: attempt.dns,
        dnsServers: dnsServers,
        allowInsecure: allowInsecure || attempt.insecure,
      );
      if (blockedApps != null) {
        addLog(
          LogLevel.info,
          'Mode Game: ${blockedApps.length} aplikasi dikecualikan dari tunnel',
        );
      }
      _disconnectSignals = 0;
      await _core!.startV2Ray(
        remark: 'BugTunnel • ${node.name}',
        config: config,
        blockedApps: blockedApps,
      );
      addLog(LogLevel.info, 'Perintah start dikirim, menunggu status...');

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));

        // Xray kadang langsung mengirim DISCONNECTED. Tidak perlu menunggu
        // 10 detik penuh sebelum mencoba server berikutnya.
        if (_disconnectSignals >= 2 && tunnel != TunnelState.connected) {
          addLog(
            LogLevel.warning,
            '${node.name} (${attempt.mode}) langsung terputus oleh core',
          );
          try {
            await _core!.stopV2Ray();
          } catch (_) {
            // Layanan mungkin sudah berhenti sendiri.
          }
          _markDead(node);
          return _ConnectOutcome.failed;
        }

        if (tunnel == TunnelState.connected) {
          connectedSince = DateTime.now();
          _prefs.setString(_kSelected, node.raw);
          _persistCache();
          notice = null;
          addLog(
            LogLevel.success,
            'Terhubung ke ${node.name} (${attempt.mode})',
          );

          // Diagnostik saja. Dengan dns=direct query DNS keluar lewat jaringan
          // Android, jadi sukses di sini TIDAK membuktikan tunnel bisa internet.
          final dns = await DnsProbe.check(server: dnsServers.first);
          if (dns.ok == true) {
            addLog(LogLevel.info, 'DNS ${dns.message} (mode ${attempt.dns})');
          } else if (dns.ok == false) {
            addLog(
              LogLevel.warning,
              'DNS lewat ${attempt.dns} gagal: ${dns.message}',
            );
          } else {
            addLog(LogLevel.info, 'DNS tidak bisa diuji: ${dns.message}');
          }

          // Penentu sukses: HTTPS sungguhan lewat SOCKS5 Xray.
          final internet = await TunnelProbe.check();
          if (!internet.ok) {
            addLog(
              LogLevel.warning,
              'Tes internet lewat tunnel gagal: ${internet.message}',
            );
            await _core!.stopV2Ray();
            tunnel = TunnelState.disconnected;
            connectedSince = null;
            _stopTicker();
            return _ConnectOutcome.tunnelFailed;
          }

          addLog(
            LogLevel.success,
            'Tes internet lewat tunnel OK: ${internet.message}',
          );
          _dnsSuccess[node.raw] = attempt.dns;
          await _persistDnsSuccess();
          addLog(
            LogLevel.success,
            'Mode DNS ${attempt.dns} disimpan untuk server ini.',
          );
          return _ConnectOutcome.connected;
        }
      }

      addLog(
        LogLevel.warning,
        '${node.name} (${attempt.mode}) tidak terhubung dalam 10 detik',
      );
      await _core!.stopV2Ray();
      _markDead(node);
      return _ConnectOutcome.failed;
    } catch (error) {
      _markDead(node);
      lastError = '${node.name} gagal: $error';
      addLog(LogLevel.error, lastError!);
      try {
        await _core!.stopV2Ray();
      } catch (_) {
        // Abaikan kegagalan saat membersihkan koneksi.
      }
      return _ConnectOutcome.failed;
    }
  }

  void _markDead(ServerNode node) {
    servers = servers.map((item) {
      if (item.id != node.id) return item;
      return item.copyWith(alive: false, clearLatency: true);
    }).toList();
  }

  Future<void> disconnect() async {
    if (busy) return;
    busy = true;
    tunnel = TunnelState.disconnecting;
    _notify();

    try {
      await _core?.stopV2Ray();
    } catch (_) {
      // Tetap anggap terputus walau layanan sudah mati.
    }

    addLog(LogLevel.info, 'Koneksi diputuskan');
    tunnel = TunnelState.disconnected;
    connectedSince = null;
    traffic = null;
    _stopTicker();
    busy = false;
    _notify();
  }

  void setBugHost(String value) {
    bugHost = value.trim();
    _prefs.setString(_kBugHost, bugHost);
    addLog(
      LogLevel.info,
      'Bug host diubah: ${bugHost.isEmpty ? 'dikosongkan' : bugHost} '
      '(SNI: ${bugHostSni ? 'ya' : 'tidak'})',
    );
    _notify();
  }

  Future<void> setBugHostSni(bool value) async {
    bugHostSni = value;
    await _prefs.setBool(_kBugHostSni, value);
    addLog(
      LogLevel.warning,
      bugHostSni
          ? 'Bug host juga dipakai sebagai SNI pada node tanpa SNI sendiri'
          : 'Bug host hanya dipakai sebagai header Host',
    );
    _notify();
  }

  Future<void> setDnsMode(String value) async {
    dnsMode = value == 'proxy' ? 'proxy' : 'direct';
    await _prefs.setString(_kDnsMode, dnsMode);
    addLog(
      LogLevel.info,
      'Mode DNS diubah: ${dnsMode == 'proxy' ? 'lewat server' : 'langsung'}',
    );
    _notify();
  }

  Future<void> setDnsServer(String value) async {
    dnsServer = value == 'google' || value == 'cloudflare' ? value : 'auto';
    await _prefs.setString(_kDnsServer, dnsServer);
    addLog(LogLevel.info, 'Resolver DNS diubah: $dnsServerLabel');
    _notify();
  }

  Future<void> setAllowInsecure(bool value) async {
    allowInsecure = value;
    await _prefs.setBool(_kAllowInsecure, value);
    addLog(
      value ? LogLevel.warning : LogLevel.info,
      value
          ? 'TLS insecure diaktifkan: verifikasi sertifikat Xray dilewati'
          : 'TLS insecure dinonaktifkan: sertifikat Xray diverifikasi',
    );
    _notify();
  }

  Future<void> setGameMode(bool value) async {
    gameMode = value;
    await _prefs.setBool(_kGameMode, value);
    addLog(
      LogLevel.info,
      value
          ? 'Mode Game aktif: hanya ${allowedApps.length} aplikasi yang lewat tunnel'
          : 'Mode Game nonaktif: semua aplikasi lewat tunnel',
    );
    _notify();
  }

  Future<void> setAllowedApps(List<String> value) async {
    final cleaned = <String>[];
    for (final item in value) {
      final package = item.trim();
      if (package.isNotEmpty && !cleaned.contains(package))
        cleaned.add(package);
    }
    allowedApps = cleaned;
    await _prefs.setStringList(_kAllowedApps, allowedApps);
    addLog(
      LogLevel.info,
      allowedApps.isEmpty
          ? 'Daftar aplikasi Mode Game dikosongkan'
          : '${allowedApps.length} aplikasi diizinkan lewat tunnel',
    );
    _notify();
  }

  Future<void> setSources(List<String> value) async {
    final cleaned = _extractUrls(value);
    sources = cleaned.isEmpty
        ? List<String>.from(ServerSource.defaults)
        : cleaned;
    await _prefs.setStringList(_kSources, sources);
    final nonEmpty = value.where((item) => item.trim().isNotEmpty).length;
    final dropped = nonEmpty > cleaned.length ? nonEmpty - cleaned.length : 0;
    addLog(
      LogLevel.info,
      'Sumber server diubah: ${sources.length} URL'
      '${dropped > 0 ? ' ($dropped baris bukan URL dibuang)' : ''}',
    );
    _notify();
  }

  Future<void> setAutoSelect(bool value) async {
    autoSelect = value;
    await _prefs.setBool(_kAutoSelect, value);
    if (value) _autoPick();
    _notify();
  }

  Future<void> setAutoUpdate(bool value) async {
    autoUpdate = value;
    await _prefs.setBool(_kAutoUpdate, value);
    _notify();
  }

  Future<ReleaseInfo?> checkForUpdate({bool silent = false}) async {
    if (checkingUpdate) return null;
    checkingUpdate = true;
    _notify();

    try {
      addLog(LogLevel.info, 'Memeriksa pembaruan...');
      final latest = await UpdateService.fetchLatest();
      if (latest == null) {
        if (!silent) notice = 'Tidak bisa memeriksa pembaruan sekarang.';
        addLog(LogLevel.warning, 'Pembaruan tidak bisa diperiksa');
        return null;
      }
      if (UpdateService.isNewer(latest.version, appVersion)) {
        update = latest;
        updatePromptPending = true;
        addLog(
          LogLevel.info,
          'Versi ${latest.version} tersedia (terpasang $appVersion)',
        );
        return latest;
      }
      update = null;
      addLog(LogLevel.info, 'Sudah memakai versi terbaru ($appVersion)');
      if (!silent) notice = 'Kamu sudah memakai versi terbaru ($appVersion).';
      return null;
    } catch (error) {
      if (!silent) notice = 'Gagal memeriksa pembaruan: $error';
      addLog(LogLevel.warning, 'Gagal memeriksa pembaruan: $error');
      return null;
    } finally {
      checkingUpdate = false;
      _notify();
    }
  }

  Future<void> openUpdate() async {
    final url = update?.apkUrl ?? update?.htmlUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) notice = 'Tidak bisa membuka tautan unduhan.';
    } catch (_) {
      notice = 'Tidak bisa membuka tautan unduhan.';
    }
    _notify();
  }

  Future<void> openRepo() async {
    try {
      await launchUrl(
        Uri.parse('https://github.com/${UpdateService.repository}'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Tidak ada yang bisa dilakukan bila browser tidak tersedia.
    }
  }

  void clearMessages() {
    lastError = null;
    notice = null;
    _notify();
  }

  Future<void> resetSettings() async {
    bugHost = '';
    bugHostSni = false;
    dnsMode = 'direct';
    dnsServer = 'auto';
    allowInsecure = false;
    gameMode = false;
    allowedApps = const [
      'com.roblox.client',
      'com.tencent.ig',
      'com.levelinfinite.gst',
      'com.supercell.clashofclans',
    ];
    _dnsSuccess.clear();
    sources = List<String>.from(ServerSource.defaults);
    autoSelect = true;
    autoUpdate = true;
    selected = null;
    servers = [];
    serversError = null;
    lastError = null;
    notice = null;
    update = null;

    await _prefs.remove(_kBugHost);
    await _prefs.remove(_kBugHostSni);
    await _prefs.remove(_kDnsMode);
    await _prefs.remove(_kDnsServer);
    await _prefs.remove(_kDnsSuccess);
    await _prefs.remove(_kAllowInsecure);
    await _prefs.remove(_kGameMode);
    await _prefs.remove(_kAllowedApps);
    await _prefs.remove(_kSources);
    await _prefs.remove(_kAutoSelect);
    await _prefs.remove(_kAutoUpdate);
    await _prefs.remove(_kSelected);
    await _prefs.remove(_kCache);
    addLog(LogLevel.info, 'Pengaturan direset');
    _notify();
  }

  Future<void> _persistDnsSuccess() async {
    await _prefs.setString(_kDnsSuccess, jsonEncode(_dnsSuccess));
  }

  void _persistCache() {
    final data = servers.take(250).map((node) => node.toJson()).toList();
    _prefs.setString(_kCache, jsonEncode(data));
    final current = selected;
    if (current != null) _prefs.setString(_kSelected, current.raw);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _startupUpdate?.cancel();
    _ticker?.cancel();
    _serverSource.dispose();
    _core?.stopV2Ray();
    super.dispose();
  }
}
