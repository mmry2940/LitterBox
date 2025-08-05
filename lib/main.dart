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
    await configureNetworkTools(appDocDirectory.path, enableDebugging: false);
  } catch (e) {
    // Fallback configuration if path_provider fails
    await configureNetworkTools('', enableDebugging: false);
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
            title: 'SSHuttle',
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

// ...existing code...
