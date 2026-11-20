import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme.dart';
import 'widgets.dart';

class ServersPage extends StatelessWidget {
  const ServersPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final alive = state.servers.where((node) => node.alive).length;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Server',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Pilih manual atau biarkan otomatis',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: state.loadingServers ? null : state.pingServers,
                    tooltip: 'Uji ulang ping',
                    icon: const Icon(Icons.speed_rounded),
                  ),
                  IconButton(
                    onPressed: state.loadingServers
                        ? null
                        : state.refreshServers,
                    tooltip: 'Muat ulang',
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Pilih server tercepat otomatis',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
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
              ),
            ),
            if (state.loadingServers)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.accent,
                backgroundColor: AppColors.surface,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  Text(
                    '${state.servers.length} server',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                    ),
                  ),
                  const Spacer(),
                  if (alive > 0)
                    Pill(
                      text: '$alive aktif',
                      color: AppColors.accent,
                      icon: Icons.check_circle_rounded,
                    ),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        );
      },
    );
  }

  Widget _body() {
    if (state.servers.isEmpty) {
      if (state.loadingServers) return const _SkeletonList();
      if (state.serversError != null) {
        return EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Server belum bisa dimuat',
          message: state.serversError!,
          action: FilledButton.icon(
            onPressed: state.refreshServers,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Coba lagi'),
          ),
        );
      }
      return EmptyState(
        icon: Icons.dns_outlined,
        title: 'Belum ada server',
        message: 'Muat daftar server gratis untuk mulai. Kamu juga bisa menambah sumber sendiri di Pengaturan.',
        action: FilledButton.icon(
          onPressed: state.refreshServers,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Muat daftar server'),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: state.servers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final node = state.servers[index];
        return _ServerRow(
          node: node,
          selected: state.selected?.id == node.id,
          onTap: () {
            state.selectServer(node);
          },
        );
      },
    );
  }
}

class _ServerRow extends StatelessWidget {
  const _ServerRow({
    required this.node,
    required this.selected,
    required this.onTap,
  });

  final ServerNode node;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withOpacity(0.08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  node.protocol,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: AppColors.accentAlt,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      node.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      node.endpoint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  LatencyBadge(latencyMs: node.latencyMs, alive: node.alive),
                  const SizedBox(height: 6),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 16,
                    color: selected ? AppColors.accent : AppColors.border,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) {
        return Container(
          height: 68,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
        );
      },
    );
  }
}
