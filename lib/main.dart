import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/session/session.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/presentation/welcome_screen.dart';
import 'features/safety/state/safety_store.dart';
import 'features/shell/presentation/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // SFamily is portrait-only for now. Revisit if a tablet layout is added.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Read any stored token before the first frame, so a signed-in user never
  // sees the welcome screen flash past.
  await Session.instance.restore();

  // Drop cached safety state when the user signs out.
  Session.instance.onSignOut(SafetyStore.instance.clear);

  runApp(const SFamilyApp());
}

class SFamilyApp extends StatelessWidget {
  const SFamilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SFamily',
      debugShowCheckedModeBanner: false,

      // The palette is dark-only, so the app does not follow the system theme.
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,

      home: AnimatedBuilder(
        animation: Session.instance,
        builder: (context, _) => Session.instance.isAuthenticated
            ? const AppShell()
            : const WelcomeScreen(),
      ),
    );
  }
}
