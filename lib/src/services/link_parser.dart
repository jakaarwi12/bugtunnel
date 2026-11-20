import 'dart:convert';

import '../models.dart';

const _supportedSchemes = {'vmess', 'vless', 'trojan', 'ss'};

/// Membaca satu langganan (subscription) berisi banyak link server.
///
/// Mendukung daftar link biasa, langganan base64, dan JSON sederhana
/// dengan kunci `servers`, `links`, `configs`, `list`, atau `data`.
List<ServerNode> parseSubscription(String body, {String source = ''}) {
  final text = body.trim();
  if (text.isEmpty) return const [];

  final rawLinks = <String>[];

  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      _collectJson(jsonDecode(text), rawLinks);
    } catch (_) {
      // Bukan JSON yang valid; lanjut sebagai teks biasa.
    }
  }

  if (rawLinks.isEmpty) {
    var content = text;
    if (!content.contains('://')) {
      final decoded = _decodeBase64(content);
      if (decoded != null && decoded.contains('://')) {
        content = decoded;
      }
    }
    for (final line in content.split(RegExp(r'[\r\n]+'))) {
      final value = line.trim();
      if (value.isEmpty) continue;
      if (value.startsWith('//')) continue;
      if (value.startsWith('#') && !value.startsWith('#vmess')) continue;
      if (!value.contains('://')) continue;
      rawLinks.add(value);
    }
  }

  final nodes = <ServerNode>[];
  final seen = <String>{};
  for (final link in rawLinks.take(1200)) {
    final node = parseServerLink(link, source: source);
    if (node == null) continue;
    if (!seen.add(node.id)) continue;
    nodes.add(node);
    if (nodes.length >= 600) break;
  }
  return nodes;
}

/// Mengubah satu link share menjadi [ServerNode].
ServerNode? parseServerLink(String raw, {String source = ''}) {
  final value = raw.trim();
  final schemeEnd = value.indexOf('://');
  if (schemeEnd <= 0) return null;

  final scheme = value.substring(0, schemeEnd).toLowerCase();
  if (!_supportedSchemes.contains(scheme)) return null;

  if (scheme == 'vmess') return _parseVmess(value, source);

  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return null;

  final port = uri.hasPort ? uri.port : 443;
  if (port <= 0 || port > 65535) return null;

  if (scheme == 'ss' && !uri.hasPort) {
    return _parseLegacyShadowsocks(value, source);
  }

  return ServerNode(
    raw: value,
    name: _fragmentName(uri) ?? uri.host,
    protocol: switch (scheme) {
      'vless' => 'VLESS',
      'trojan' => 'Trojan',
      'ss' => 'SS',
      _ => scheme.toUpperCase(),
    },
    address: uri.host,
    port: port,
    source: source,
  );
}

ServerNode? _parseVmess(String value, String source) {
  final payload = value.substring(8).split('#').first;
  final decoded = _decodeBase64(payload);
  if (decoded == null) return null;

  final dynamic data;
  try {
    data = jsonDecode(decoded);
  } catch (_) {
    return null;
  }
  if (data is! Map) return null;

  final address = (data['add'] ?? '').toString().trim();
  final port = int.tryParse((data['port'] ?? '443').toString()) ?? 443;
  if (address.isEmpty || port <= 0 || port > 65535) return null;

  final rawName = (data['ps'] ?? data['remarks'] ?? data['name'] ?? address)
      .toString()
      .trim();

  return ServerNode(
    raw: value,
    name: rawName.isEmpty ? address : rawName,
    protocol: 'VMess',
    address: address,
    port: port,
    source: source,
  );
}

ServerNode? _parseLegacyShadowsocks(String value, String source) {
  final payload = value.substring(5).split('#').first;
  final decoded = _decodeBase64(payload);
  if (decoded == null) return null;

  final at = decoded.lastIndexOf('@');
  if (at <= 0) return null;

  final hostPort = decoded.substring(at + 1);
  final colon = hostPort.lastIndexOf(':');
  if (colon <= 0) return null;

  final host = hostPort.substring(0, colon).trim();
  final port = int.tryParse(hostPort.substring(colon + 1).trim());
  if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;

  return ServerNode(
    raw: value,
    name: host,
    protocol: 'SS',
    address: host,
    port: port,
    source: source,
  );
}

String? _fragmentName(Uri uri) {
  if (uri.fragment.isEmpty) return null;
  try {
    final decoded = Uri.decodeComponent(uri.fragment).trim();
    return decoded.isEmpty ? null : decoded;
  } catch (_) {
    return null;
  }
}

String? _decodeBase64(String input) {
  var value = input.trim().replaceAll(RegExp(r'\s+'), '');
  if (value.isEmpty) return null;
  value = value.replaceAll('-', '+').replaceAll('_', '/');
  final remainder = value.length % 4;
  if (remainder != 0) {
    value = value.padRight(value.length + (4 - remainder), '=');
  }
  try {
    return utf8.decode(base64.decode(value));
  } catch (_) {
    return null;
  }
}

void _collectJson(dynamic value, List<String> out) {
  if (value is String) {
    if (value.contains('://')) out.add(value);
    return;
  }
  if (value is List) {
    for (final item in value) {
      _collectJson(item, out);
    }
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString().toLowerCase();
      if (key == 'servers' ||
          key == 'links' ||
          key == 'configs' ||
          key == 'list' ||
          key == 'data') {
        _collectJson(entry.value, out);
      } else if (entry.value is String &&
          (entry.value as String).contains('://')) {
        out.add(entry.value as String);
      }
    }
  }
}
