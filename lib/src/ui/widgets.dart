import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/installed_apps.dart';
import '../theme.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.accent, AppColors.accentAlt],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Icon(Icons.bolt_rounded, color: AppColors.bg, size: size * 0.62),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.text,
    this.color = AppColors.accent,
    this.icon,
  });

  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class LatencyBadge extends StatelessWidget {
  const LatencyBadge({super.key, this.latencyMs, this.alive = false});

  final int? latencyMs;
  final bool alive;

  @override
  Widget build(BuildContext context) {
    final ms = latencyMs;
    final color = !alive || ms == null
        ? AppColors.muted
        : ms < 150
        ? AppColors.accent
        : ms < 400
        ? AppColors.warning
        : AppColors.danger;
    final text = !alive || ms == null ? 'mati' : '$ms ms';
    return Pill(
      text: text,
      color: color,
      icon: alive ? Icons.speed_rounded : Icons.cloud_off_rounded,
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.icon,
  });

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: AppColors.muted),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(icon, size: 32, color: AppColors.muted),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final decimals = value >= 100 || index == 0 ? 0 : 1;
  return '${value.toStringAsFixed(decimals)} ${units[index]}';
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : AppColors.surfaceAlt,
    ),
  );
}

Future<void> showBugHostDialog(BuildContext context, AppState state) async {
  final controller = TextEditingController(text: state.bugHost);
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Bug host'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Default: hanya dipakai sebagai header Host pada server WS/HTTP/gRPC. SNI tidak diubah. Aktifkan "Bug host sebagai SNI" di Pengaturan hanya bila server memang memerlukannya — SNI salah sering membuat TLS gagal.',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'contoh: bug.example.com',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (result != null) state.setBugHost(result);
}

Future<void> showSourcesDialog(BuildContext context, AppState state) async {
  final controller = TextEditingController(text: state.sources.join('\n'));
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Sumber server'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Satu URL per baris. Bisa berupa daftar link langsung atau langganan base64.',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 210,
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontSize: 12, height: 1.5),
                  decoration: const InputDecoration(hintText: 'https://...'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Simpan'),
          ),
        ],
      );
    },
  );
  controller.dispose();
  if (result != null) {
    final lines = result
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    await state.setSources(lines);
  }
}

Future<void> showDnsServerDialog(BuildContext context, AppState state) async {
  var selected = state.dnsServer;
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocalState) {
          return AlertDialog(
            title: const Text('Resolver DNS'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Resolver dipakai Xray saat menyambung dan saat tes DNS. Pilih otomatis untuk mencoba 8.8.8.8 lalu 1.1.1.1.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RadioGroup<String>(
                    groupValue: selected,
                    onChanged: (value) {
                      if (value == null) return;
                      setLocalState(() {
                        selected = value;
                      });
                    },
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RadioListTile<String>(
                          value: 'auto',
                          contentPadding: EdgeInsets.zero,
                          title: Text('Otomatis'),
                          subtitle: Text('8.8.8.8 + 1.1.1.1'),
                        ),
                        RadioListTile<String>(
                          value: 'google',
                          contentPadding: EdgeInsets.zero,
                          title: Text('Google'),
                          subtitle: Text('8.8.8.8'),
                        ),
                        RadioListTile<String>(
                          value: 'cloudflare',
                          contentPadding: EdgeInsets.zero,
                          title: Text('Cloudflare'),
                          subtitle: Text('1.1.1.1'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      );
    },
  );
  if (result == null) return;
  if (!context.mounted) return;
  await state.setDnsServer(result);
}

Future<void> showAllowedAppsDialog(BuildContext context, AppState state) async {
  final future = InstalledApps.load();
  final selected = state.allowedApps.toSet();
  final searchController = TextEditingController();
  var query = '';
  final result = await showDialog<Set<String>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setLocalState) {
          return AlertDialog(
            title: const Text('Aplikasi yang diizinkan'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hanya aplikasi terpilih yang lewat tunnel saat Mode Game aktif. Aplikasi lain memakai koneksi biasa.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    onChanged: (value) {
                      setLocalState(() {
                        query = value;
                      });
                    },
                    decoration: const InputDecoration(
                      hintText: 'Cari aplikasi atau package',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 320,
                    child: FutureBuilder<List<InstalledApp>>(
                      future: future,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          );
                        }
                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                              'Gagal membaca daftar aplikasi terpasang.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.danger,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }
                        final needle = query.trim().toLowerCase();
                        final apps =
                            (snapshot.data ?? const <InstalledApp>[]).where((
                              app,
                            ) {
                              if (needle.isEmpty) return true;
                              final name = app.appName.toLowerCase();
                              final package = app.packageName.toLowerCase();
                              return name.contains(needle) ||
                                  package.contains(needle);
                            }).toList()..sort(
                              (a, b) => a.appName.toLowerCase().compareTo(
                                b.appName.toLowerCase(),
                              ),
                            );
                        if (apps.isEmpty) {
                          return const Center(
                            child: Text(
                              'Tidak ada aplikasi yang cocok.',
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }
                        return ListView.builder(
                          itemCount: apps.length,
                          itemBuilder: (context, index) {
                            final app = apps[index];
                            final checked = selected.contains(app.packageName);
                            return CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: checked,
                              title: Text(
                                app.appName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              subtitle: Text(
                                app.packageName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                              onChanged: (value) {
                                setLocalState(() {
                                  if (value == true) {
                                    selected.add(app.packageName);
                                  } else {
                                    selected.remove(app.packageName);
                                  }
                                });
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      );
    },
  );
  searchController.dispose();
  if (result == null) return;
  if (!context.mounted) return;
  await state.setAllowedApps(result.toList());
}
