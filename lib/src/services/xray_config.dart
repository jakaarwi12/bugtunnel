import 'dart:convert';

import 'package:flutter_v2ray/flutter_v2ray.dart';

import '../models.dart';

class XrayConfig {
  /// Membangun konfigurasi Xray dari link server.
  ///
  /// Selain menimpa SNI/header Host dengan bug host, konfigurasi ini juga
  /// memperbaiki routing yang dipakai plugin:
  ///
  /// - DNS (port 53) dikirim langsung, bukan lewat proxy. Banyak server gratis
  ///   tidak mendukung UDP, sehingga DNS lewat proxy membuat aplikasi seperti
  ///   Chrome dan YouTube seolah "tidak ada internet" walau ping ke IP jalan.
  /// - Alamat privat/LAN tetap langsung agar tidak dipaksa lewat server.
  /// - Sniffing diaktifkan supaya domain tujuan terbaca.
  static String build(ServerNode node, {String bugHost = ''}) {
    final parser = parseV2RayURL(node.raw);
    final map =
        jsonDecode(parser.getFullConfiguration()) as Map<String, dynamic>;
    final host = bugHost.trim();

    _enableSniffing(map);
    _applyRouting(map);
    _applyDns(map);

    if (host.isNotEmpty) {
      _applyBugHost(map, host);
      // SNI diganti, jadi sertifikat server tidak akan cocok dengan nama host
      // baru. Tanpa ini, TLS gagal dan semua koneksi mati.
      _setAllowInsecure(map);
    } else if (_wantsInsecure(node.raw)) {
      _setAllowInsecure(map);
    }

    return jsonEncode(map);
  }

  static void _enableSniffing(Map<String, dynamic> config) {
    final inbounds = config['inbounds'];
    if (inbounds is! List) return;
    for (final item in inbounds) {
      if (item is! Map) continue;
      item['sniffing'] = {
        'enabled': true,
        'destOverride': ['http', 'tls'],
        'metadataOnly': false,
        'routeOnly': false,
      };
    }
  }

  static void _applyRouting(Map<String, dynamic> config) {
    config['routing'] = {
      // Jangan paksa Xray menyelesaikan domain untuk pencocokan aturan.
      // Domain hasil sniffing diteruskan apa adanya ke server.
      'domainStrategy': 'AsIs',
      'rules': [
        {'type': 'field', 'port': '53', 'outboundTag': 'direct'},
        {
          'type': 'field',
          'ip': [
            '10.0.0.0/8',
            '172.16.0.0/12',
            '192.168.0.0/16',
            '127.0.0.0/8',
            '169.254.0.0/16',
            'fc00::/7',
            'fe80::/10',
          ],
          'outboundTag': 'direct',
        },
      ],
      'balancers': <dynamic>[],
    };
  }

  static void _applyDns(Map<String, dynamic> config) {
    config['dns'] = {
      'servers': ['8.8.8.8', '1.1.1.1'],
    };
  }

  /// Ringkasan konfigurasi yang aman ditampilkan di log.
  ///
  /// Tidak pernah memuat id/password/URL lengkap.
  static String describe(ServerNode node, {String bugHost = ''}) {
    final map =
        jsonDecode(build(node, bugHost: bugHost)) as Map<String, dynamic>;
    final outbounds = map['outbounds'];

    Map<dynamic, dynamic>? proxy;
    if (outbounds is List) {
      for (final item in outbounds) {
        if (item is Map &&
            item['protocol'] != 'freedom' &&
            item['protocol'] != 'blackhole') {
          proxy = item;
          break;
        }
      }
    }

    final stream = proxy?['streamSettings'];
    final network = stream is Map ? stream['network'] : null;
    final security = stream is Map ? stream['security'] : null;

    String? sni;
    String? host;
    var insecure = false;
    if (stream is Map) {
      final tls = stream['tlsSettings'];
      if (tls is Map) {
        sni = tls['serverName']?.toString();
        insecure = tls['allowInsecure'] == true;
      }
      final ws = stream['wsSettings'];
      if (ws is Map && ws['headers'] is Map) {
        host = (ws['headers'] as Map)['Host']?.toString();
      }
    }

    return '${node.protocol} ${node.endpoint} '
        'net=${network ?? '-'} security=${security ?? '-'} '
        'sni=${sni ?? '-'} host=${host ?? '-'} insecure=$insecure';
  }

  static void _applyBugHost(Map<String, dynamic> config, String bugHost) {
    final outbounds = config['outbounds'];
    if (outbounds is! List) return;

    for (final item in outbounds) {
      if (item is! Map) continue;
      final protocol = item['protocol']?.toString() ?? '';
      if (protocol == 'freedom' ||
          protocol == 'blackhole' ||
          protocol == 'dns') {
        continue;
      }

      final stream = item['streamSettings'];
      if (stream is! Map) continue;

      final security = stream['security']?.toString() ?? '';
      if (security == 'tls' || security == 'xtls') {
        final tls = _asMap(stream['tlsSettings']);
        tls['serverName'] = bugHost;
        stream['tlsSettings'] = tls;
      } else if (security == 'reality') {
        final reality = _asMap(stream['realitySettings']);
        reality['serverName'] = bugHost;
        stream['realitySettings'] = reality;
      }

      final network = stream['network']?.toString() ?? '';
      if (network == 'ws') {
        final ws = _asMap(stream['wsSettings']);
        final headers = _asMap(ws['headers']);
        headers['Host'] = bugHost;
        ws['headers'] = headers;
        stream['wsSettings'] = ws;
      } else if (network == 'http' || network == 'h2') {
        final http = _asMap(stream['httpSettings']);
        http['host'] = [bugHost];
        stream['httpSettings'] = http;
      } else if (network == 'grpc') {
        final grpc = _asMap(stream['grpcSettings']);
        grpc['authority'] = bugHost;
        stream['grpcSettings'] = grpc;
      } else if (network == 'tcp') {
        final tcp = stream['tcpSettings'];
        if (tcp is Map) {
          final tcpMap = _asMap(tcp);
          final header = _asMap(tcpMap['header']);
          if (header['type']?.toString() == 'http') {
            final request = _asMap(header['request']);
            final headers = _asMap(request['headers']);
            headers['Host'] = [bugHost];
            request['headers'] = headers;
            header['request'] = request;
            tcpMap['header'] = header;
            stream['tcpSettings'] = tcpMap;
          }
        }
      }
    }
  }

  static void _setAllowInsecure(Map<String, dynamic> config) {
    final outbounds = config['outbounds'];
    if (outbounds is! List) return;
    for (final item in outbounds) {
      if (item is! Map) continue;
      final stream = item['streamSettings'];
      if (stream is! Map) continue;
      final security = stream['security']?.toString() ?? '';
      if (security == 'tls' || security == 'xtls') {
        final tls = _asMap(stream['tlsSettings']);
        tls['allowInsecure'] = true;
        stream['tlsSettings'] = tls;
      }
    }
  }

  /// Menghormati tautan yang memang meminta verifikasi sertifikat dilewati.
  static bool _wantsInsecure(String raw) {
    final lower = raw.toLowerCase();
    return lower.contains('allowinsecure=1') ||
        lower.contains('allowinsecure=true') ||
        lower.contains('"allowinsecure":true') ||
        lower.contains('"allowinsecure":"1"') ||
        lower.contains('skip-cert-verify=true');
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}
