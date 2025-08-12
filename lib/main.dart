import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_breakpoints/flutter_breakpoints.dart';
import 'package:path_provider/path_provider.dart';
import 'package:network_tools/network_tools.dart';
import 'screens/settings_screen.dart';
import 'screens/home_screen.dart';

final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier(ThemeMode.dark);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure network tools - required for network_tools package
  try {
    final appDocDirectory = await getApplicationDocumentsDirectory();
    await configureNetworkTools(appDocDirectory.path, enableDebugging: true);
    print('Network tools configured with path: \\${appDocDirectory.path}');
  } catch (e) {
    print('Failed to get app directory, using fallback: $e');
    // Fallback configuration if path_provider fails
    await configureNetworkTools('', enableDebugging: true);
  }

  // Determine the splash image to use
  final splashImages = [
    'assets/splash_1.jpg',
    'assets/splash_2.jpg',
    'assets/splash_3.jpg',
  ];
  final random = Random();
  final splashImage = splashImages[random.nextInt(splashImages.length)];

  runApp(MyApp(splashImage: splashImage));
}

class MyApp extends StatelessWidget {
  final String? splashImage;

  const MyApp({super.key, this.splashImage});

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
            home: SplashScreen(splashImage: splashImage ?? 'assets/splash_1.jpg'),
            routes: {
              '/settings': (context) => const SettingsScreen(),
              '/home': (context) => const HomeScreen(),
            },
          ),
        );
      },
    );
  }
}

class SplashScreen extends StatelessWidget {
  final String? splashImage;

  const SplashScreen({super.key, this.splashImage});

  @override
  Widget build(BuildContext context) {
  // Navigate to the main screen after a delay
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const HomeScreen()),
      );
    });

    return Scaffold(
      body: Center(
  child: Image.asset(splashImage ?? 'assets/splash_1.jpg'),
      ),
    );
  }
}

class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsScreen();
  }
}
