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
/// The artwork is drawn for this screen: 1:2.224, with the scene in the top
/// 58% and deliberately empty gradient below it. So it covers the whole
/// screen and the wordmark, promise and the two ways in sit on the empty
/// part, with no drawn background of our own underneath.
///
/// Cover rather than contain, anchored to the top. On a screen taller than
/// the artwork the sides overflow by a few percent — which is why the source
/// image keeps every element clear of its outer edges. Anchoring to the top
/// means anything trimmed vertically comes off the empty bottom, never off
/// the family.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({
    super.key,
    this.onLogin,
    this.onCreateAccount,
  });

  final VoidCallback? onLogin;
  final VoidCallback? onCreateAccount;

  /// The artwork's own bottom colour, sampled from the file. Used for the
  /// scaffold and the scrim so nothing behind the image is a different hue.
  static const Color _artworkBase = Color(0xFF0F015B);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 720;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: _artworkBase,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // The artwork, full screen.
            Positioned.fill(
              child: Image.asset(
                AppAssets.welcomeScreen,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),

            // A light scrim under the text.
            //
            // Tinted with the artwork's own bottom colour rather than the
            // app's navy — they are different hues, and fading one into the
            // other leaves a visible colour shift across the lower third.
            //
            // It also stops short of opaque: the artwork's bottom is already
            // dark and near-empty, so all this needs to do is lift contrast a
            // little. Painting it out would hide the swirls the image was
            // drawn to keep.
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
                      Color(0x000F015B),
                      Color(0x800F015B),
                      Color(0xB30F015B),
                    ],
                    stops: [0.0, 0.5, 1.0],
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
