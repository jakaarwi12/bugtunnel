import 'dart:convert';

import 'package:flutter_v2ray/flutter_v2ray.dart';

import '../models.dart';

class XrayConfig {
  /// Membangun konfigurasi Xray dari link server, lalu menimpa SNI/header
  /// Host dengan bug host bila diisi.
  static String build(ServerNode node, {String bugHost = ''}) {
    final parser = parseV2RayURL(node.raw);
    final map =
        jsonDecode(parser.getFullConfiguration()) as Map<String, dynamic>;
    final host = bugHost.trim();
    if (host.isNotEmpty) {
      _applyBugHost(map, host);
    }
    return jsonEncode(map);
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

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }
}
