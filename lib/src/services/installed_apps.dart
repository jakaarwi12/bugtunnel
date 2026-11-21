import 'package:flutter/services.dart';

/// Aplikasi pengguna yang bisa dipilih untuk Mode Game.
class InstalledApp {
  const InstalledApp({required this.packageName, required this.appName});

  final String packageName;
  final String appName;
}

/// Jembatan ke `MainActivity.kt` untuk membaca daftar aplikasi terpasang.
///
/// Memakai method channel sendiri, bukan plugin pihak ketiga, karena plugin
/// lama masih memakai `jcenter()` yang sudah dihapus dari Gradle modern.
class InstalledApps {
  static const MethodChannel _channel = MethodChannel(
    'com.jakaarwi.bugtunnel/apps',
  );

  static Future<List<InstalledApp>> load() async {
    final value = await _channel.invokeListMethod<dynamic>('getInstalledApps');
    if (value == null) return const [];
    final result = <InstalledApp>[];
    for (final item in value) {
      if (item is! Map) continue;
      final package = item['package']?.toString().trim() ?? '';
      final name = item['name']?.toString().trim() ?? '';
      if (package.isEmpty) continue;
      result.add(
        InstalledApp(
          packageName: package,
          appName: name.isEmpty ? package : name,
        ),
      );
    }
    result.sort(
      (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
    );
    return result;
  }
}
