import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            const Text(
              'Pengaturan',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Semua pengaturan disimpan di perangkat ini.',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('Koneksi'),
            SectionCard(
              child: Column(
                children: [
                  _SettingRow(
                    icon: Icons.bug_report_rounded,
                    title: 'Bug host',
                    subtitle: state.bugHost.isEmpty
                        ? 'Belum diatur (opsional)'
                        : state.bugHost,
                    onTap: () => showBugHostDialog(context, state),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.muted,
                    ),
                  ),
                  const Divider(),
                  _SwitchRow(
                    icon: Icons.public_rounded,
                    title: 'Bug host sebagai SNI',
                    subtitle: 'Nonaktif: aman. Aktif: SNI ikut diganti',
                    value: state.bugHostSni,
                    onChanged: (value) {
                      state.setBugHostSni(value);
                    },
                  ),
                  const Divider(),
                  _SwitchRow(
                    icon: Icons.dns_outlined,
                    title: 'DNS lewat server',
                    subtitle: 'Aktifkan bila DNS langsung tidak menjawab',
                    value: state.dnsMode == 'proxy',
                    onChanged: (value) {
                      state.setDnsMode(value ? 'proxy' : 'direct');
                    },
                  ),
                  const Divider(),
                  _SwitchRow(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Server otomatis',
                    subtitle: 'Pilih server tercepat saat daftar dimuat',
                    value: state.autoSelect,
                    onChanged: (value) {
                      state.setAutoSelect(value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _SectionLabel('Sumber server'),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingRow(
                    icon: Icons.link_rounded,
                    title: 'Daftar URL sumber',
                    subtitle: '${state.sources.length} sumber aktif',
                    onTap: () => showSourcesDialog(context, state),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Server berasal dari daftar publik. Ketersediaan berubah-ubah; kalau banyak yang mati, muat ulang atau tambahkan sumber milikmu.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _SectionLabel('Pembaruan'),
            SectionCard(
              child: Column(
                children: [
                  _SwitchRow(
                    icon: Icons.system_update_rounded,
                    title: 'Cek pembaruan otomatis',
                    subtitle: 'Bandingkan versi dengan rilis GitHub',
                    value: state.autoUpdate,
                    onChanged: (value) {
                      state.setAutoUpdate(value);
                    },
                  ),
                  const Divider(),
                  _SettingRow(
                    icon: Icons.refresh_rounded,
                    title: 'Cek sekarang',
                    subtitle:
                        'Versi terpasang ${state.appVersion} (${state.appBuild})',
                    onTap: state.checkingUpdate
                        ? null
                        : () => _checkForUpdate(context),
                    trailing: state.checkingUpdate
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.accent,
                            ),
                          )
                        : const Icon(
                            Icons.chevron_right_rounded,
                            color: AppColors.muted,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const _SectionLabel('Tentang'),
            SectionCard(
              child: Column(
                children: [
                  _SettingRow(
                    icon: Icons.code_rounded,
                    title: 'Repositori GitHub',
                    subtitle: 'jakaarwi12/bugtunnel',
                    onTap: () {
                      state.openRepo();
                    },
                    trailing: const Icon(
                      Icons.open_in_new_rounded,
                      color: AppColors.muted,
                      size: 18,
                    ),
                  ),
                  const Divider(),
                  _SettingRow(
                    icon: Icons.delete_outline_rounded,
                    title: 'Reset pengaturan',
                    subtitle: 'Hapus bug host, sumber, dan cache server',
                    onTap: () => _confirmReset(context),
                    trailing: const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Catatan',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'BugTunnel tidak memiliki atau menjual server. Aplikasi hanya membaca daftar server publik yang kamu tentukan. Gunakan sesuai hukum yang berlaku dan hanya untuk tujuan yang sah.',
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _checkForUpdate(BuildContext context) async {
    final release = await state.checkForUpdate();
    if (!context.mounted) return;
    if (release == null) {
      showMessage(context, state.notice ?? 'Kamu sudah memakai versi terbaru.');
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Reset pengaturan?'),
          content: const Text(
            'Bug host, sumber server, dan cache server akan dihapus. Tindakan ini tidak bisa dibatalkan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
    if (ok == true) {
      await state.resetSettings();
      if (context.mounted) showMessage(context, 'Pengaturan sudah direset.');
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: AppColors.muted,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: AppColors.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
