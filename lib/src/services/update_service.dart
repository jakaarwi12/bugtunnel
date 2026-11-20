import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

class UpdateService {
  static const String repository = 'jakaarwi12/bugtunnel';
  static const String _latestRelease =
      'https://api.github.com/repos/$repository/releases/latest';

  static Future<ReleaseInfo?> fetchLatest() async {
    final response = await http
        .get(
          Uri.parse(_latestRelease),
          headers: const {
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'BugTunnel',
          },
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) return null;

    final dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      return null;
    }
    if (data is! Map) return null;

    final tag = (data['tag_name'] ?? '').toString();
    if (tag.isEmpty) return null;

    String? apkUrl;
    final assets = data['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is Map) {
          final url = (asset['browser_download_url'] ?? '').toString();
          if (url.toLowerCase().endsWith('.apk')) {
            apkUrl = url;
            break;
          }
        }
      }
    }

    return ReleaseInfo(
      tag: tag,
      name: (data['name'] ?? tag).toString(),
      notes: (data['body'] ?? '').toString(),
      htmlUrl: (data['html_url'] ?? 'https://github.com/$repository/releases')
          .toString(),
      apkUrl: apkUrl,
    );
  }

  static bool isNewer(String latest, String current) {
    final left = _parts(latest);
    final right = _parts(current);
    for (var index = 0; index < 3; index++) {
      if (left[index] != right[index]) return left[index] > right[index];
    }
    return false;
  }

  static List<int> _parts(String version) {
    final cleaned = version.replaceFirst(RegExp(r'^[vV]'), '').split('+').first;
    final pieces = cleaned.split('.');
    return List.generate(3, (index) {
      if (index >= pieces.length) return 0;
      return int.tryParse(pieces[index]) ?? 0;
    });
  }
}
