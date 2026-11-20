import 'package:flutter/material.dart';

import '../app_state.dart';
import 'home_page.dart';
import 'servers_page.dart';
import 'settings_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.state});

  final AppState state;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;
  bool _updateDialogOpen = false;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowUpdate());
  }

  void _onStateChanged() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowUpdate());
  }

  Future<void> _maybeShowUpdate() async {
    if (!mounted || _updateDialogOpen) return;
    final state = widget.state;
    final release = state.update;
    if (!state.updatePromptPending || release == null) return;

    state.updatePromptPending = false;
    _updateDialogOpen = true;

    final notes = release.notes.trim();
    final preview = notes.length > 1200
        ? '${notes.substring(0, 1200)}\n...'
        : notes;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: Text('Versi ${release.version} tersedia'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ada pembaruan BugTunnel. Unduh APK terbaru dari halaman rilis GitHub.',
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    preview,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Nanti'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                state.openUpdate();
              },
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Unduh'),
            ),
          ],
        );
      },
    );

    _updateDialogOpen = false;
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: [
            HomePage(
              state: widget.state,
              onOpenServers: () => setState(() => _index = 1),
            ),
            ServersPage(state: widget.state),
            SettingsPage(state: widget.state),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.bolt_rounded),
            selectedIcon: Icon(Icons.bolt_rounded),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.dns_outlined),
            selectedIcon: Icon(Icons.dns_rounded),
            label: 'Server',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Pengaturan',
          ),
        ],
      ),
    );
  }
}
