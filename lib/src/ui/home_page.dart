import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';
import 'widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state, required this.onOpenServers});

  final AppState state;
  final VoidCallback onOpenServers;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            _Header(state: state),
            const SizedBox(height: 20),
            if (state.update != null) ...[
              _UpdateBanner(state: state),
              const SizedBox(height: 12),
            ],
            if (state.lastError != null) ...[
              _ErrorBanner(state: state),
              const SizedBox(height: 12),
            ],
            if (state.notice != null) ...[
              _NoticeBanner(state: state),
              const SizedBox(height: 12),
            ],
            _ConnectPanel(state: state),
            const SizedBox(height: 14),
            _ServerTile(state: state, onTap: onOpenServers),
            const SizedBox(height: 12),
            _BugHostTile(state: state),
            const SizedBox(height: 12),
            _AutoTile(state: state),
            if (state.isConnected) ...[
              const SizedBox(height: 12),
              _Stats(state: state),
            ],
            const SizedBox(height: 18),
            const _Footnote(),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final connected = state.isConnected;
    final connecting = state.tunnel == TunnelState.connecting;
    return Row(
      children: [
        const AppLogo(),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BugTunnel',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Server gratis tercepat, otomatis',
                style: TextStyle(color: AppColors.muted, fontSize: 11),
              ),
            ],
          ),
        ),
        Pill(
          text: state.statusLabel,
          color: connected
              ? AppColors.accent
              : connecting
              ? AppColors.warning
              : AppColors.muted,
          icon: connected
              ? Icons.shield_rounded
              : connecting
              ? Icons.sync_rounded
              : Icons.circle_outlined,
        ),
      ],
    );
  }
}

class _ConnectPanel extends StatelessWidget {
  const _ConnectPanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final connected = state.isConnected;
    final working =
        state.busy ||
        state.tunnel == TunnelState.connecting ||
        state.tunnel == TunnelState.disconnecting;

    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Column(
        children: [
          _ConnectButton(state: state),
          const SizedBox(height: 18),
          Text(
            state.statusLabel,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: connected ? AppColors.accent : AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            connected
                ? (state.selected?.name ?? 'Terhubung')
                : working
                ? 'Mohon tunggu sebentar...'
                : 'Ketuk tombol untuk menyambung',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (connected) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Pill(
                  text: 'Aktif',
                  color: AppColors.accent,
                  icon: Icons.lock_rounded,
                ),
                const SizedBox(width: 8),
                Pill(
                  text: formatDuration(state.connectedDuration),
                  color: AppColors.accentAlt,
                  icon: Icons.timer_outlined,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final connected = state.isConnected;
    final working =
        state.busy ||
        state.tunnel == TunnelState.connecting ||
        state.tunnel == TunnelState.disconnecting;

    return Semantics(
      button: true,
      label: connected ? 'Putuskan koneksi' : 'Sambungkan koneksi',
      child: GestureDetector(
        onTap: working
            ? null
            : () {
                state.toggleConnection();
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          width: 188,
          height: 188,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: connected
                  ? const [AppColors.accent, AppColors.accentAlt]
                  : const [AppColors.surfaceAlt, AppColors.surface],
            ),
            boxShadow: [
              BoxShadow(
                color: (connected ? AppColors.accent : Colors.black)
                    .withOpacity(connected ? 0.42 : 0.3),
                blurRadius: connected ? 46 : 22,
                spreadRadius: connected ? 6 : 0,
                offset: const Offset(0, 12),
              ),
            ],
            border: Border.all(
              color: connected ? AppColors.accent : AppColors.border,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (working)
                const SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.accent,
                  ),
                )
              else
                Icon(
                  connected
                      ? Icons.shield_rounded
                      : Icons.power_settings_new_rounded,
                  size: 56,
                  color: connected ? AppColors.bg : AppColors.accent,
                ),
              const SizedBox(height: 12),
              Text(
                connected
                    ? 'TERHUBUNG'
                    : working
                    ? 'PROSES'
                    : 'TERPUTUS',
                style: TextStyle(
                  color: connected ? AppColors.bg : AppColors.text,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  const _ServerTile({required this.state, required this.onTap});

  final AppState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final node = state.selected;
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.dns_rounded,
              color: AppColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  node?.name ?? 'Belum ada server',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  node?.endpoint ?? 'Muat daftar server untuk memulai',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (node != null) ...[
            const SizedBox(width: 8),
            LatencyBadge(latencyMs: node.latencyMs, alive: node.alive),
          ],
          IconButton(
            onPressed: onTap,
            tooltip: 'Pilih server',
            icon: const Icon(Icons.swap_horiz_rounded),
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}

class _BugHostTile extends StatelessWidget {
  const _BugHostTile({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accentAlt.withOpacity(0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.bug_report_rounded,
              color: AppColors.accentAlt,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Bug host',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 3),
                Text(
                  state.bugHost.isEmpty
                      ? 'Belum diatur (opsional)'
                      : state.bugHost,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => showBugHostDialog(context, state),
            child: const Text('Ubah'),
          ),
        ],
      ),
    );
  }
}

class _AutoTile extends StatelessWidget {
  const _AutoTile({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server otomatis',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                SizedBox(height: 3),
                Text(
                  'Pilih server dengan ping terendah',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Switch(
            value: state.autoSelect,
            onChanged: (value) {
              state.setAutoSelect(value);
            },
          ),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: 'Durasi',
            value: formatDuration(state.connectedDuration),
            icon: Icons.timer_outlined,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            label: 'Unduh',
            value: formatBytes(state.traffic?.download ?? 0),
            icon: Icons.download_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            label: 'Unggah',
            value: formatBytes(state.traffic?.upload ?? 0),
            icon: Icons.upload_rounded,
          ),
        ),
      ],
    );
  }
}

class _UpdateBanner extends StatelessWidget {
  const _UpdateBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      color: AppColors.accent.withOpacity(0.08),
      child: Row(
        children: [
          const Icon(Icons.system_update_rounded, color: AppColors.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Versi ${state.update!.version} tersedia',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Ketuk untuk mengunduh pembaruan',
                  style: TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              state.openUpdate();
            },
            child: const Text('Unduh'),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      color: AppColors.danger.withOpacity(0.08),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.danger),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.lastError!,
              style: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            onPressed: state.clearMessages,
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      color: AppColors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: AppColors.muted,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.notice!,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'BugTunnel tidak memiliki server. Daftar server dibaca dari sumber publik yang bisa kamu ubah di Pengaturan.',
      textAlign: TextAlign.center,
      style: TextStyle(color: AppColors.muted, fontSize: 10, height: 1.5),
    );
  }
}
