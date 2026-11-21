import 'dart:convert';
import 'dart:io';

import 'package:flutter_v2ray/flutter_v2ray.dart';

import '../models.dart';

class XrayConfig {
  /// Membangun konfigurasi Xray dari link server.
  ///
  /// [overrideSni] menentukan apakah bug host juga mengganti SNI. Default
  /// hanya mengganti header Host, karena banyak server memakai SNI sendiri
  /// dan menolak SNI lain.
  ///
  /// [dnsMode] `direct` mengirim DNS (port 53) lewat jaringan langsung,
  /// `proxy` membiarkannya lewat server.
  ///
  /// [dnsServers] diisi alamat IP resolver, misalnya `1.1.1.1` (Cloudflare).
  static String build(
    ServerNode node, {
    String bugHost = '',
    bool overrideSni = false,
    String dnsMode = 'direct',
    List<String> dnsServers = const ['8.8.8.8', '1.1.1.1'],
  }) {
    final parser = parseV2RayURL(node.raw);
    final map =
        jsonDecode(parser.getFullConfiguration()) as Map<String, dynamic>;
    final host = bugHost.trim();

    // Xray >= 26.7.11 Menolak seluruh konfigurasi bila field lama ini masih
    // ada, termasuk ketika berasal dari link langganan publik.
    _stripRemovedFields(map);
    _enableSniffing(map);
    _applyRouting(map, dnsMode);
    _applyDns(map, dnsServers);

    if (host.isNotEmpty) {
      _applyBugHost(map, host, overrideSni: overrideSni);
    }

    return jsonEncode(map);
  }

  /// Mengembalikan alasan server tidak mungkin dipakai, atau null bila valid.
  ///
  /// Sejak Xray 26.7.11, VLESS tanpa TLS/REALITY maupun VLESS Encryption
  /// ditolak untuk alamat publik (IP maupun domain biasa). Node seperti ini
  /// selalu gagal di tahap parse, jadi lebih baik dilewati lebih awal.
  static String? validationError(ServerNode node) {
    try {
      final parser = parseV2RayURL(node.raw);
      final map =
          jsonDecode(parser.getFullConfiguration()) as Map<String, dynamic>;
      final outbounds = map['outbounds'];
      if (outbounds is! List) return null;

      for (final item in outbounds) {
        if (item is! Map) continue;
        if (item['protocol'] != 'vless') continue;
        final stream = item['streamSettings'];
        final security = stream is Map
            ? (stream['security']?.toString() ?? '')
            : '';
        if (security.isNotEmpty && security != 'none') continue;

        // VLESS Encryption juga memenuhi syarat Xray.
        final settings = item['settings'];
        final encryption = settings is Map
            ? settings['encryption']?.toString().trim() ?? ''
            : '';
        if (encryption.isNotEmpty && encryption != 'none') continue;

        if (_isPrivateHost(node.address)) continue;
        return 'VLESS tanpa TLS/enkripsi ke alamat publik ditolak Xray';
      }
    } catch (_) {
      // Konfigurasi rusak akan gagal di tahap lain.
    }
    return null;
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

  static void _applyRouting(Map<String, dynamic> config, String dnsMode) {
    final dnsTarget = dnsMode == 'proxy' ? _proxyTag(config) : 'direct';
    final rules = <Map<String, dynamic>>[
      // Query DNS yang dibuat Xray sendiri ikut mode yang dipilih.
      {
        'type': 'field',
        'inboundTag': const ['dns_query'],
        'outboundTag': dnsTarget,
      },
      // DNS dari aplikasi (lewat TUN → SOCKS) memakai port 53.
      {'type': 'field', 'port': '53', 'outboundTag': dnsTarget},
      {
        'type': 'field',
        'ip': const [
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
    ];

    config['routing'] = {
      'domainStrategy': 'AsIs',
      'rules': rules,
      'balancers': <dynamic>[],
    };
  }

  static void _applyDns(Map<String, dynamic> config, List<String> servers) {
    final cleaned = servers
        .map((item) => item.trim())
        .where((item) => InternetAddress.tryParse(item) != null)
        .toList();
    config['dns'] = {
      'servers': cleaned.isEmpty ? const ['8.8.8.8'] : cleaned,
      'queryStrategy': 'UseIPv4',
      'tag': 'dns_query',
    };
  }

  /// True bila link server sudah menanam SNI TLS/REALITY sendiri.
  ///
  /// Node seperti ini tidak boleh dipaksa memakai SNI bug host: Xray akan
  /// menolak konfigurasi atau server menolak handshake TLS.
  static bool hasOwnSni(ServerNode node) {
    try {
      final map = jsonDecode(
        parseV2RayURL(node.raw).getFullConfiguration(),
      ) as Map<String, dynamic>;
      final outbounds = map['outbounds'];
      if (outbounds is! List) return false;
      for (final item in outbounds) {
        if (item is! Map) continue;
        if (item['protocol'] == 'freedom' || item['protocol'] == 'blackhole') {
          continue;
        }
        final stream = item['streamSettings'];
        if (stream is! Map) continue;
        for (final key in const ['tlsSettings', 'realitySettings']) {
          final tls = stream[key];
          if (tls is Map &&
              tls['serverName']?.toString().trim().isNotEmpty == true) {
            return true;
          }
        }
      }
    } catch (_) {
      // Konfigurasi rusak ditangani di tempat lain.
    }
    return false;
  }

  static String _proxyTag(Map<String, dynamic> config) {
    final outbounds = config['outbounds'];
    if (outbounds is List) {
      for (final item in outbounds) {
        if (item is! Map) continue;
        final protocol = item['protocol']?.toString() ?? '';
        if (protocol == 'freedom' || protocol == 'blackhole') continue;
        final tag = item['tag']?.toString();
        if (tag != null && tag.isNotEmpty) return tag;
      }
    }
    return 'proxy';
  }

  /// Ringkasan konfigurasi yang aman ditampilkan di log.
  static String describe(
    ServerNode node, {
    String bugHost = '',
    bool overrideSni = false,
    String dnsMode = 'direct',
    List<String> dnsServers = const ['8.8.8.8', '1.1.1.1'],
  }) {
    final map = jsonDecode(
      build(
        node,
        bugHost: bugHost,
        overrideSni: overrideSni,
        dnsMode: dnsMode,
        dnsServers: dnsServers,
      ),
    ) as Map<String, dynamic>;
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
    if (stream is Map) {
      final tls = stream['tlsSettings'];
      if (tls is Map) {
        sni = tls['serverName']?.toString();
      }
      final reality = stream['realitySettings'];
      if (reality is Map) {
        sni ??= reality['serverName']?.toString();
      }
      final ws = stream['wsSettings'];
      if (ws is Map && ws['headers'] is Map) {
        host = (ws['headers'] as Map)['Host']?.toString();
      }
      for (final key in const ['h2Setting', 'httpSettings']) {
        final settings = stream[key];
        if (settings is Map && settings['host'] is List) {
          final list = (settings['host'] as List);
          if (list.isNotEmpty) host = list.first.toString();
        }
      }
    }

    return '${node.protocol} ${node.endpoint} '
        'net=${network ?? '-'} security=${security ?? '-'} '
        'sni=${sni ?? '-'} host=${host ?? '-'} '
        'sniMode=${overrideSni ? 'bug' : 'asli'} dns=$dnsMode';
  }

  static void _applyBugHost(
    Map<String, dynamic> config,
    String bugHost, {
    required bool overrideSni,
  }) {
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

      if (overrideSni) {
        final security = stream['security']?.toString() ?? '';
        if (security == 'tls' || security == 'xtls') {
          final tls = _asMap(stream['tlsSettings']);

          // Xray menghapus allowInsecure. Pengganti resminya untuk domain
          // fronting adalah verifyPeerCertByName: nama asli dipakai untuk
          // verifikasi sertifikat, sementara SNI di kabel tetap bug host.
          final originalSni = tls['serverName']?.toString().trim() ?? '';
          if (originalSni.isNotEmpty) {
            tls['verifyPeerCertByName'] = originalSni;
          }
          tls['serverName'] = bugHost;
          stream['tlsSettings'] = tls;
        } else if (security == 'reality') {
          final reality = _asMap(stream['realitySettings']);
          reality['serverName'] = bugHost;
          stream['realitySettings'] = reality;
        }
      }

      final network = stream['network']?.toString() ?? '';
      if (network == 'ws') {
        final ws = _asMap(stream['wsSettings']);
        final headers = _asMap(ws['headers']);
        headers['Host'] = bugHost;
        ws['headers'] = headers;
        stream['wsSettings'] = ws;
      } else if (network == 'http' || network == 'h2') {
        for (final key in const ['h2Setting', 'httpSettings']) {
          if (stream[key] is Map) {
            final http = _asMap(stream[key]);
            http['host'] = [bugHost];
            stream[key] = http;
          }
        }
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

  /// Membuang field TLS yang sudah dihapus Xray.
  ///
  /// Xray 26.7.11+ menganggap `allowInsecure` sebagai konfigurasi invalid dan
  /// menolak seluruh outbound. Field ini sering masih tertanam di link gratis.
  static void _stripRemovedFields(dynamic value) {
    if (value is List) {
      for (final item in value) {
        _stripRemovedFields(item);
      }
      return;
    }
    if (value is! Map) return;

    final map = value as Map<dynamic, dynamic>;
    for (final key in map.keys.toList()) {
      final lower = key.toString().toLowerCase();
      if (lower == 'allowinsecure' || lower == 'verifypeercertinnames') {
        map.remove(key);
      } else {
        _stripRemovedFields(map[key]);
      }
    }
  }

  static bool _isPrivateHost(String raw) {
    final host = raw.trim().toLowerCase();
    final address = InternetAddress.tryParse(host);
    if (address != null) {
      final bytes = address.rawAddress;
      if (address.type == InternetAddressType.IPv4) {
        return bytes[0] == 10 ||
            bytes[0] == 127 ||
            (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
            (bytes[0] == 192 && bytes[1] == 168) ||
            (bytes[0] == 169 && bytes[1] == 254);
      }
      if (bytes.length >= 2) {
        if ((bytes[0] & 0xFE) == 0xFC) return true;
        if (bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80) return true;
      }
      return false;
    }
    return host == 'localhost' ||
        host.endsWith('.local') ||
        host.endsWith('.lan') ||
        host.endsWith('.internal') ||
        host.endsWith('.home.arpa') ||
        host.endsWith('.test');
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}
