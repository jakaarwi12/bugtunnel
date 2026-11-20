import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';
import 'link_parser.dart';

class ServerSource {
  static const List<String> defaults = [
    'https://raw.githubusercontent.com/peasoft/NoMoreWalls/master/list.txt',
    'https://raw.githubusercontent.com/ermaozi/get_subscribe/main/subscribe/v2ray.txt',
    'https://raw.githubusercontent.com/mahdibland/ShadowsocksAggregator/master/Eternity.txt',
    'https://raw.githubusercontent.com/ripaojiedian/freenode/main/sub',
    'https://raw.githubusercontent.com/freefq/free/master/v2',
  ];

  final http.Client _client = http.Client();

  Future<List<ServerNode>> fetchAll(
    List<String> sources, {
    void Function(String url, int count)? onSource,
  }) async {
    final unique = sources
        .map((source) => source.trim())
        .where((source) => source.isNotEmpty)
        .toSet()
        .toList();
    if (unique.isEmpty) return const [];

    final results = await Future.wait(unique.map(_fetchOne));
    final merged = <ServerNode>[];
    final seen = <String>{};
    for (var index = 0; index < results.length; index++) {
      final list = results[index];
      onSource?.call(unique[index], list.length);
      for (final node in list) {
        if (seen.add(node.id)) merged.add(node);
      }
    }
    return merged;
  }

  Future<List<ServerNode>> _fetchOne(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
        return const [];
      }
      final response = await _client
          .get(
            uri,
            headers: const {
              'User-Agent':
                  'BugTunnel/1.0 (+https://github.com/jakaarwi12/bugtunnel)',
              'Accept': 'text/plain, application/json, */*',
            },
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) return const [];
      if (response.bodyBytes.length > 4 * 1024 * 1024) return const [];

      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      return parseSubscription(body, source: url);
    } catch (_) {
      return const [];
    }
  }

  void dispose() {
    _client.close();
  }
}
