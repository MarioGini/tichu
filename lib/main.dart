import 'package:material_ui/material_ui.dart';

import 'package:tichu/agents/app_bots.dart';
import 'package:tichu/screens/home/home_screen.dart';
import 'package:tichu/services/multiplayer/configured_multiplayer_backend.dart';
import 'package:tichu/services/multiplayer/multiplayer_backend.dart';
import 'package:tichu/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppBots.load();

  try {
    final multiplayerBackend = await createConfiguredMultiplayerBackend();
    runApp(MyApp(multiplayerBackend: multiplayerBackend));
  } on Object catch (error) {
    runApp(_BootstrapErrorApp(error: error));
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, final MultiplayerBackend? multiplayerBackend})
    : _multiplayerBackend = multiplayerBackend;

  final MultiplayerBackend? _multiplayerBackend;

  @override
  Widget build(final BuildContext context) => MaterialApp(
    title: 'Tichu',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: ThemeMode.dark,
    home: HomeScreen(multiplayerBackend: _multiplayerBackend),
  );
}

class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({required this.error});

  final Object error;

  @override
  Widget build(final BuildContext context) => MaterialApp(
    title: 'Tichu',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: ThemeMode.dark,
    home: Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    'Multiplayer backend failed to initialize.',
                    style: Theme.of(context).textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$error',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
