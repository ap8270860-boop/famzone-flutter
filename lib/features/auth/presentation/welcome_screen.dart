import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'widgets/glow_buttons.dart';
import 'widgets/sfamily_wordmark.dart';

/// The first screen a user sees.
///
/// The artwork covers the full screen; the wordmark, promise and the two
/// ways in are drawn straight onto it, in the empty area the artwork
/// leaves below the feature cards.
/// The first screen a user sees.
///
/// The artwork fills the top of the screen at its natural aspect ratio,
/// so nothing is cropped from the sides. The wordmark, promise and the
/// two ways in are real widgets over its lower edge.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    this.onLogin,
    this.onCreateAccount,
  });

  final VoidCallback? onLogin;
  final VoidCallback? onCreateAccount;

  /// Artwork is 1024 x 1536.
  static const double _artworkAspect = 1536 / 1024;

  /// Sampled from the artwork's bottom edge, so the painted image and the
  /// drawn background meet without a visible seam.
  static const Color _seam = Color(0xFF01114B);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final artworkHeight = size.width * _artworkAspect;
    final compact = size.height < 720;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppColors.deepNavy,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Carries the artwork's colours down past its bottom edge.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_seam, Color(0xFF0A1247), AppColors.deepNavy],
                  stops: [0.0, 0.45, 1.0],
                ),
              ),
            ),

            // The artwork: full width, top aligned, never cropped sideways.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: artworkHeight,
              child: Image.asset(
                AppAssets.welcomeScreen,
                fit: BoxFit.fitWidth,
                alignment: Alignment.topCenter,
              ),
            ),

            // Soften the artwork's bottom edge into the background.
            Positioned(
              top: artworkHeight - 90,
              left: 0,
              right: 0,
              height: 90,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x0001114B), _seam],
                  ),
                ),
              ),
            ),

            // Scrim so the swirls never fight the text.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: compact ? 300 : 340,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00050D2C),
                      Color(0xCC050D2C),
                      Color(0xFF050D2C),
                    ],
                    stops: [0.0, 0.42, 0.72],
                  ),
                ),
              ),
            ),

            // Wordmark, promise, values, actions.
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(22, 0, 22, compact ? 10 : 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SFamilyWordmark(fontSize: compact ? 40 : 48),
                      SizedBox(height: compact ? 8 : 12),
                      const _Tagline(),
                      SizedBox(height: compact ? 10 : 16),
                      const _ValueStrip(),
                      SizedBox(height: compact ? 14 : 22),
                      GradientActionButton(
                        label: 'LOGIN',
                        onPressed: onLogin ?? () => _open(context, const LoginScreen()),
                      ),
                      const SizedBox(height: 12),
                      OutlineActionButton(
                        label: 'CREATE ACCOUNT',
                        onPressed: onCreateAccount ??
                            () => _open(context, const RegisterScreen()),
                      ),
                      SizedBox(height: compact ? 10 : 14),
                      const _Footer(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: RichText(
        textAlign: TextAlign.center,
        text: const TextSpan(
          style: TextStyle(
            fontSize: 14.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
            color: AppColors.softWhite,
          ),
          children: [
            TextSpan(text: "Your Family's "),
            TextSpan(text: 'Safety', style: TextStyle(color: AppColors.neonCyan)),
            TextSpan(text: ', '),
            TextSpan(text: 'Care', style: TextStyle(color: Color(0xFF8B7BEA))),
            TextSpan(text: ',\n'),
            TextSpan(text: 'Happiness', style: TextStyle(color: AppColors.warmGold)),
            TextSpan(text: ' & '),
            TextSpan(
              text: 'AI Companion',
              style: TextStyle(color: AppColors.neonCyan),
            ),
            TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}

class _ValueStrip extends StatelessWidget {
  const _ValueStrip();

  static const List<(IconData, String, Color)> _items = [
    (Icons.shield_rounded, 'Stay Safe', AppColors.neonCyan),
    (Icons.favorite_rounded, 'Stay Connected', AppColors.neonPink),
    (Icons.volunteer_activism_rounded, 'Be Kind', AppColors.emerald),
    (Icons.sentiment_very_satisfied_rounded, 'Be Happy', AppColors.warmGold),
    (Icons.auto_awesome_rounded, 'Live Better', AppColors.neonPurple),
  ];

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (icon, label, tint) in _items) ...[
            Icon(icon, size: 11, color: tint),
            const SizedBox(width: 3),
            Text(
              label,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: AppColors.lavenderGray,
              ),
            ),
            if (label != _items.last.$2) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: const TextSpan(
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: AppColors.lavenderGray,
        ),
        children: [
          TextSpan(text: 'Your Family. Your World. '),
          TextSpan(
            text: 'SFamily',
            style: TextStyle(
              color: AppColors.neonCyan,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: '.'),
        ],
      ),
    );
  }
}
