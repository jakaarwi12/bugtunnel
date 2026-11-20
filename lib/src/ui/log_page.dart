import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../log.dart';
import '../theme.dart';
import 'widgets.dart';

class LogPage extends StatelessWidget {
  const LogPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final entries = state.logs.reversed.toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Log',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Detail koneksi, error Xray, dan status server',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tes server terpilih',
                    onPressed: () async {
                      await state.testSelectedServer();
                      if (context.mounted) {
                        showMessage(context, 'Tes server selesai. Lihat log.');
                      }
                    },
                    icon: const Icon(Icons.speed_rounded),
                    color: AppColors.accent,
                  ),
                  IconButton(
                    tooltip: 'Ambil log sistem',
                    onPressed: () async {
                      await state.captureSystemLog();
                      if (context.mounted) {
                        showMessage(context, 'Log sistem ditambahkan.');
                      }
                    },
                    icon: const Icon(Icons.terminal_rounded),
                    color: AppColors.accentAlt,
                  ),
                  IconButton(
                    tooltip: 'Hapus log',
                    onPressed: state.logs.isEmpty
                        ? null
                        : () {
                            state.clearLogs();
                            showMessage(context, 'Log dihapus.');
                          },
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: AppColors.muted,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Pill(
                    text: '${state.logs.length} baris',
                    color: AppColors.muted,
                    icon: Icons.article_outlined,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: state.logs.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(
                              ClipboardData(text: state.exportLogs()),
                            );
                            if (context.mounted) {
                              showMessage(context, 'Semua log disalin.');
                            }
                          },
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Salin semua'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: entries.isEmpty
                  ? const EmptyState(
                      icon: Icons.article_outlined,
                      title: 'Belum ada log',
                      message: 'Log muncul saat aplikasi memuat server dan mencoba menyambung. Tekan tombol besar di Beranda atau muat ulang daftar server.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        return _LogRow(entry: entries[index]);
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.level) {
      LogLevel.success => AppColors.accent,
      LogLevel.warning => AppColors.warning,
      LogLevel.error => AppColors.danger,
      LogLevel.info => AppColors.muted,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.clock,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 9,
              fontFamily: 'monospace',
              height: 1.6,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 38,
            child: Text(
              entry.label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                height: 1.6,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SelectableText(
              entry.message,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
