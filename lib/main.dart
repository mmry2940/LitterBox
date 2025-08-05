import 'package:flutter/material.dart';
import 'package:flutter_breakpoints/flutter_breakpoints.dart';
import 'package:path_provider/path_provider.dart';
import 'package:network_tools/network_tools.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';

final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.dark);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure network tools - required for network_tools package
  try {
    final appDocDirectory = await getApplicationDocumentsDirectory();
    await configureNetworkTools(appDocDirectory.path, enableDebugging: true);
    print('Network tools configured with path: ${appDocDirectory.path}');
  } catch (e) {
    print('Failed to get app directory, using fallback: $e');
    // Fallback configuration if path_provider fails
    await configureNetworkTools('', enableDebugging: true);
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        return FlutterBreakpointProvider.builder(
          context: context,
          child: MaterialApp(
            title: 'LitterBox',
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.deepPurple, brightness: Brightness.light),
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.deepPurple, brightness: Brightness.dark),
            ),
            themeMode: mode,
            home: const HomeScreen(),
            routes: {'/settings': (context) => const SettingsScreen()},
          ),
        );
      },
    );
  }
}
