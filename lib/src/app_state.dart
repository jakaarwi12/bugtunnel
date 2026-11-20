import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_v2ray/flutter_v2ray.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'models.dart';
import 'services/latency.dart';
import 'services/server_source.dart';
import 'services/update_service.dart';
import 'services/xray_config.dart';

enum TunnelState { disconnected, connecting, connected, disconnecting }

class AppState extends ChangeNotifier {
  static const _kBugHost = 'bug_host';
  static const _kSources = 'sources';
  static const _kAutoSelect = 'auto_select';
  static const _kAutoUpdate = 'auto_update';
  static const _kSelected = 'selected_raw';
  static const _kCache = 'server_cache';

  final ServerSource _serverSource = ServerSource();
  late SharedPreferences _prefs;

  String bugHost = '';
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
  ReleaseInfo? update;
  bool updatePromptPending = false;

  FlutterV2ray? _core;
  bool _coreReady = false;
  bool _disposed = false;
  Timer? _ticker;
  Timer? _startupUpdate;

  bool get isAndroid => Platform.isAndroid;
  bool get isConnected => tunnel == TunnelState.connected;

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

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    bugHost = _prefs.getString(_kBugHost) ?? '';
    autoSelect = _prefs.getBool(_kAutoSelect) ?? true;
    autoUpdate = _prefs.getBool(_kAutoUpdate) ?? true;

    final storedSources = _prefs.getStringList(_kSources);
    if (storedSources != null && storedSources.isNotEmpty) {
      sources = storedSources;
    }

    _restoreCache();

    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = info.version;
      appBuild = info.buildNumber;
    } catch (_) {
      // Versi tetap memakai nilai bawaan bila platform tidak mendukung.
    }

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
    } catch (error) {
      _coreReady = false;
      lastError = 'Mesin tunnel gagal disiapkan: $error';
    }
  }

  void _onStatus(V2RayStatus status) {
    if (_disposed) return;
    traffic = status;
    final value = status.state.toUpperCase();

    if (value.contains('DISCONNECT')) {
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
    _notify();

    try {
      final fetched = await _serverSource.fetchAll(sources);
      if (fetched.isEmpty) {
        serversError = 'Tidak ada server yang bisa dibaca. Periksa koneksi internet atau sumber server di Pengaturan.';
        return;
      }
      servers = await LatencyTester.rank(fetched);
      _autoPick();
      _persistCache();
    } catch (error) {
      serversError = 'Gagal memuat server: $error';
    } finally {
      loadingServers = false;
      _notify();
    }
  }

  Future<void> pingServers() async {
    if (loadingServers || servers.isEmpty) return;
    loadingServers = true;
    _notify();
    try {
      servers = await LatencyTester.rank(servers, limit: 120);
      _autoPick();
      _persistCache();
    } catch (error) {
      lastError = 'Gagal menguji server: $error';
    } finally {
      loadingServers = false;
      _notify();
    }
  }

  void _autoPick() {
    if (servers.isEmpty) {
      selected = null;
      return;
    }
    if (!autoSelect && selected != null) {
      for (final node in servers) {
        if (node.id == selected!.id) {
          selected = node;
          return;
        }
      }
    }
    for (final node in servers) {
      if (node.alive) {
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
      if (!granted) {
        lastError = 'Izin VPN ditolak. Izinkan BugTunnel membuat koneksi VPN, lalu coba lagi.';
        return;
      }

      final ordered = await _prioritize(candidates);
      for (final node in ordered) {
        if (await _tryConnect(node)) return;
      }
      lastError =
          'Semua server gagal terhubung. Coba muat ulang daftar server.';
    } catch (error) {
      lastError = 'Gagal menyambung: $error';
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

  List<ServerNode> _connectCandidates() {
    final alive = servers.where((node) => node.alive).toList();
    final pool = alive.isNotEmpty ? alive : servers;
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

  /// Menguji apakah server benar-benar bisa meneruskan trafik.
  ///
  /// Ping TCP hanya membuktikan port terbuka. Banyak server gratis menerima
  /// koneksi tetapi tidak bisa keluar ke internet. `getServerDelay` memakai
  /// core Xray untuk mengambil URL lewat server tersebut.
  Future<bool> _probe(ServerNode node) async {
    final core = _core;
    if (core == null) return false;
    try {
      final config = XrayConfig.build(node, bugHost: bugHost);
      final delay = await core
          .getServerDelay(
            config: config,
            url: 'https://www.gstatic.com/generate_204',
          )
          .timeout(const Duration(seconds: 6), onTimeout: () => -1);
      return delay > 0;
    } catch (_) {
      return false;
    }
  }

  /// Menaruh server yang lolos tes nyata di depan, tanpa membuang kandidat lain.
  Future<List<ServerNode>> _prioritize(List<ServerNode> candidates) async {
    if (candidates.length <= 1) return candidates;

    final passed = <ServerNode>[];
    final failed = <ServerNode>[];
    for (final node in candidates.take(2)) {
      if (await _probe(node)) {
        passed.add(node);
      } else {
        failed.add(node);
      }
    }
    return [...passed, ...failed, ...candidates.skip(2)];
  }

  Future<bool> _tryConnect(ServerNode node) async {
    selected = node;
    tunnel = TunnelState.connecting;
    notice = 'Mencoba ${node.name}...';
    _notify();

    try {
      final config = XrayConfig.build(node, bugHost: bugHost);
      await _core!.startV2Ray(
        remark: 'BugTunnel • ${node.name}',
        config: config,
      );

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (tunnel == TunnelState.connected) {
          connectedSince = DateTime.now();
          _prefs.setString(_kSelected, node.raw);
          _persistCache();
          notice = null;
          return true;
        }
      }

      await _core!.stopV2Ray();
      _markDead(node);
      return false;
    } catch (error) {
      _markDead(node);
      lastError = '${node.name} gagal: $error';
      try {
        await _core!.stopV2Ray();
      } catch (_) {
        // Abaikan kegagalan saat membersihkan koneksi.
      }
      return false;
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
    _notify();
  }

  Future<void> setSources(List<String> value) async {
    final cleaned = value
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    sources = cleaned.isEmpty
        ? List<String>.from(ServerSource.defaults)
        : cleaned;
    await _prefs.setStringList(_kSources, sources);
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
      final latest = await UpdateService.fetchLatest();
      if (latest == null) {
        if (!silent) notice = 'Tidak bisa memeriksa pembaruan sekarang.';
        return null;
      }
      if (UpdateService.isNewer(latest.version, appVersion)) {
        update = latest;
        updatePromptPending = true;
        return latest;
      }
      update = null;
      if (!silent) notice = 'Kamu sudah memakai versi terbaru ($appVersion).';
      return null;
    } catch (error) {
      if (!silent) notice = 'Gagal memeriksa pembaruan: $error';
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
    await _prefs.remove(_kSources);
    await _prefs.remove(_kAutoSelect);
    await _prefs.remove(_kAutoUpdate);
    await _prefs.remove(_kSelected);
    await _prefs.remove(_kCache);
    _notify();
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
