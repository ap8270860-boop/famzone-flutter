import 'package:flutter/material.dart';

/// The SFamily palette.
///
/// Single source of truth — never hard-code a hex anywhere else.
abstract final class AppColors {
  /// Primary background. Almost-black navy.
  static const Color deepNavy = Color(0xFF050D2C);

  /// Secondary background — cards, sheets, raised surfaces.
  static const Color royalNavy = Color(0xFF111F54);

  /// Primary action colour.
  static const Color electricBlue = Color(0xFF0E54CF);

  /// Highlights, links, active states.
  static const Color neonCyan = Color(0xFF12A3E7);

  static const Color neonPurple = Color(0xFF583DC4);
  static const Color indigo = Color(0xFF1F2B88);
  static const Color neonPink = Color(0xFFD559A4);

  /// Success / online / safe.
  static const Color emerald = Color(0xFF169371);

  /// Warning / pending.
  static const Color warmGold = Color(0xFFE1BC4B);

  /// Primary text on dark backgrounds.
  static const Color softWhite = Color(0xFFEEE6EB);

  /// Secondary and hint text.
  static const Color lavenderGray = Color(0xFF9DA2B9);

  // --- App shell (home, auth) ------------------------------------------
  //
  // The in-app screens sit on a near-black canvas so the glass surfaces and
  // the cyan/green accents carry the colour. Deeper than [deepNavy], which
  // belongs to the welcome artwork.

  /// Page background — the base tone at the bottom of the screen.
  static const Color canvas = Color(0xFF001528);

  /// Top of the page gradient. The header sits in this brighter band.
  static const Color canvasTop = Color(0xFF012E57);

  /// Sheets, the bottom bar and other lifted surfaces.
  static const Color canvasRaised = Color(0xFF011D2F);

  /// The whole-page wash. Sampled from the design: a bright navy at the top
  /// falling to near-black by roughly 40% down, then flat.
  static const LinearGradient appBackground = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [canvasTop, Color(0xFF011629), canvas],
    stops: [0.0, 0.40, 1.0],
  );

  /// Fill behind a glass surface, before the blur.
  static const Color glassFill = Color(0x0FFFFFFF);

  /// Border on a glass surface.
  static const Color glassBorder = Color(0x1AFFFFFF);

  /// Primary accent — the safe state.
  static const Color mint = Color(0xFF2BE07F);

  /// Secondary accent — information and links.
  static const Color aqua = Color(0xFF29D3E8);

  /// Danger — SOS and destructive actions.
  static const Color alertRed = Color(0xFFFF4D6D);

  /// Body text on the canvas.
  static const Color textPrimary = Color(0xFFEAF2FF);

  /// Supporting text, hints, disabled states.
  static const Color textMuted = Color(0xFF8A97B1);

  /// The safety-shield sweep, sampled stop by stop from the design: sky blue
  /// through turquoise and spring green into lime. Wider than
  /// [safeGradient], which is only the two mid tones.
  static const LinearGradient shieldGradient = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [
      Color(0xFF02AAF1),
      Color(0xFF11CCD1),
      Color(0xFF63D87A),
      Color(0xFFBCE72B),
    ],
    stops: [0.0, 0.35, 0.68, 1.0],
  );

  /// The SOS button sweep, sampled from the design: cyan through spring
  /// green into lime, left to right.
  static const LinearGradient sosGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF0FCFDF), Color(0xFF62E487), Color(0xFFAAE232)],
    stops: [0.0, 0.52, 1.0],
  );

  /// Unselected bottom-bar item — a muted slate, sampled from the design.
  static const Color navInactive = Color(0xFF6F8AA3);

  /// Bottom bar surface.
  static const Color barSurface = Color(0xFF01203A);

  /// The safe/primary action gradient — aqua into mint.
  static const LinearGradient safeGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [aqua, mint],
  );

  /// Brand gradient — used on the logo mark and accent surfaces.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [neonCyan, electricBlue, neonPurple],
  );

  /// Full-screen background wash.
  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [deepNavy, Color(0xFF091540), royalNavy],
    stops: [0.0, 0.55, 1.0],
  );
}
