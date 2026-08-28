/// Every bundled asset path, in one place.
///
/// Referencing `AppAssets.logoMark` instead of a raw string means a renamed
/// file breaks the build here rather than silently at runtime on a phone.
abstract final class AppAssets {
  static const String _logo = 'assets/logo';
  static const String _images = 'assets/images';
  static const String _icons = 'assets/icons';

  // --- Brand -------------------------------------------------------------

  /// Square icon mark — welcome screen, app bars, avatars.
  static const String logoMark = '$_logo/sfamily_mark.png';

  /// High-resolution master. Source for launcher-icon generation, not for
  /// rendering in the app.
  static const String logoMaster = '$_logo/sfamily_mark_1024.png';

  // --- Illustrations -----------------------------------------------------

  /// Full-screen artwork, 1:2.224. The top ~58% is the scene; the rest
  /// is empty gradient the login controls are drawn over.
  static const String welcomeScreen = '$_images/welcome-screen.png';

  /// The AI companion mascot, edges feathered for dark backgrounds.
  static const String robotMascot = '$_images/robot_mascot.png';

  // --- Feature icons -----------------------------------------------------
  //
  // Currently unused: the welcome chips draw Material icons, which are
  // sharper at small sizes and match their labels. Swap a chip over by
  // setting `asset:` on its FeatureChipData entry.

  static const String iconSafety = '$_icons/safety.png';
  static const String iconLocation = '$_icons/location.png';
  static const String iconChildSafety = '$_icons/child_safety.png';
  static const String iconWomenSafety = '$_icons/women_safety.png';
  static const String iconSeniorCare = '$_icons/senior_care.png';
  static const String iconFamilyCare = '$_icons/family_care.png';
  static const String iconChat = '$_icons/chat.png';
  static const String iconReminder = '$_icons/reminder.png';
  static const String iconHealth = '$_icons/health.png';
  static const String iconGoals = '$_icons/goals.png';
  static const String iconGames = '$_icons/games.png';
  static const String iconHappiness = '$_icons/happiness.png';
}
