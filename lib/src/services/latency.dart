import 'dart:io';
import 'dart:math';

import '../models.dart';

class LatencyTester {
  /// Mengukur waktu koneksi TCP ke server. Ini bukan tes proxy penuh,
  /// tetapi cukup untuk memilih server mana yang paling cepat merespons.
  static Future<int?> ping(
    String host,
    int port, {
    Duration timeout = const Duration(milliseconds: 2200),
  }) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      stopwatch.stop();
      return stopwatch.elapsedMilliseconds;
    } catch (_) {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  static Future<List<ServerNode>> rank(
    List<ServerNode> nodes, {
    int limit = 90,
    int batchSize = 15,
    int stopAfterAlive = 15,
  }) async {
    if (nodes.isEmpty) return const [];

    final sample = nodes.take(limit).toList();
    final tested = <ServerNode>[];
    var aliveCount = 0;

    for (var start = 0; start < sample.length; start += batchSize) {
      final chunk = sample.sublist(
        start,
        min(start + batchSize, sample.length),
      );
      final results = await Future.wait(
        chunk.map((node) async {
          final ms = await ping(node.address, node.port);
          return ServerNode(
            raw: node.raw,
            name: node.name,
            protocol: node.protocol,
            address: node.address,
            port: node.port,
            latencyMs: ms,
            alive: ms != null,
            source: node.source,
          );
        }),
      );
      tested.addAll(results);
      aliveCount += results.where((node) => node.alive).length;
      if (aliveCount >= stopAfterAlive) break;
    }

    final rest = nodes.skip(limit).map((node) {
      return ServerNode(
        raw: node.raw,
        name: node.name,
        protocol: node.protocol,
        address: node.address,
        port: node.port,
        source: node.source,
      );
    });

    final all = [...tested, ...rest];
    all.sort((a, b) {
      if (a.alive != b.alive) return a.alive ? -1 : 1;
      final left = a.latencyMs ?? (1 << 30);
      final right = b.latencyMs ?? (1 << 30);
      return left.compareTo(right);
    });
    return all;
  }
}
