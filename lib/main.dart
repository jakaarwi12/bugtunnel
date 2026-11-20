import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/app_state.dart';
import 'src/theme.dart';
import 'src/ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  final state = AppState();
  await state.init();
  runApp(BugTunnelApp(state: state));
}

class BugTunnelApp extends StatelessWidget {
  const BugTunnelApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BugTunnel',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: RootShell(state: state),
    );
  }
}
