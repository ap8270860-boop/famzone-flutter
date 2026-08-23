import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The signed-in user, as the app needs it.
///
/// A view of the API's user resource rather than a full mirror — fields get
/// added here as screens actually need them.
@immutable
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.phone,
    this.username,
    this.email,
    this.avatarUrl,
    this.timezone,
    this.userType = 'adult',
    this.phoneVerified = false,
    this.hasPassword = false,
    this.isPremium = false,
    this.aiMessagesUsed = 0,
    this.aiMessagesLimit = 5,
  });

  final String id;
  final String name;
  final String phone;
  final String? username;
  final String? email;
  final String? avatarUrl;

  /// IANA zone the server has on file, e.g. "Asia/Kolkata". Compared
  /// against the device on each sync so the day boundary follows the
  /// user when they travel.
  final String? timezone;
  final String userType;
  final bool phoneVerified;

  /// Whether a password is set. Decides whether the change-password form
  /// asks for the current one.
  final bool hasPassword;
  final bool isPremium;
  final int aiMessagesUsed;
  final int aiMessagesLimit;

  /// First name only — what the greeting uses.
  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  /// Up to two initials, for the avatar fallback.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final subscription = json['subscription'] as Map<String, dynamic>? ?? const {};

    return AuthUser(
      id: json['id']?.toString() ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      username: json['username'] as String?,
      email: json['email'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      timezone: json['timezone'] as String?,
      userType: json['user_type'] as String? ?? 'adult',
      phoneVerified: json['phone_verified'] as bool? ?? false,
      hasPassword: json['has_password'] as bool? ?? false,
      isPremium: subscription['is_premium'] as bool? ?? false,
      aiMessagesUsed: subscription['ai_messages_used'] as int? ?? 0,
      aiMessagesLimit: subscription['ai_messages_limit'] as int? ?? 5,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'username': username,
        'email': email,
        'avatar_url': avatarUrl,
        'timezone': timezone,
        'user_type': userType,
        'phone_verified': phoneVerified,
        'has_password': hasPassword,
        'subscription': {
          'is_premium': isPremium,
          'ai_messages_used': aiMessagesUsed,
          'ai_messages_limit': aiMessagesLimit,
        },
      };
}

/// Holds the auth token and current user, and persists them.
///
/// A plain [ChangeNotifier] rather than a state-management package: the
/// Riverpod-vs-Bloc decision is still open, and this is small enough to move
/// behind whichever wins without touching the screens much.
class Session extends ChangeNotifier {
  Session._();

  static final Session instance = Session._();

  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  // Encrypted SharedPreferences on Android, Keychain on iOS. A bearer token
  // has no business in plain SharedPreferences.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  String? _token;
  AuthUser? _user;
  bool _restored = false;

  String? get token => _token;
  AuthUser? get user => _user;
  bool get isAuthenticated => _token != null && _user != null;

  /// True once [restore] has run, so the app knows not to flash the welcome
  /// screen at someone who is already signed in.
  bool get restored => _restored;

  /// Load a previous session from storage. Call once, before the first frame.
  Future<void> restore() async {
    try {
      _token = await _storage.read(key: _tokenKey);
      final raw = await _storage.read(key: _userKey);
      if (raw != null) {
        _user = AuthUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // A corrupt or unreadable store should mean "signed out", never a crash
      // on launch.
      _token = null;
      _user = null;
    } finally {
      _restored = true;
      notifyListeners();
    }
  }

  Future<void> signIn({required String token, required AuthUser user}) async {
    _token = token;
    _user = user;
    notifyListeners();

    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  Future<void> updateUser(AuthUser user) async {
    _user = user;
    notifyListeners();
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  /// Called on sign-out, so other stores can drop their state.
  ///
  /// A plain callback list rather than an import of every store — Session sits
  /// under core and must not depend on features above it.
  final List<VoidCallback> _onSignOut = [];

  void onSignOut(VoidCallback callback) => _onSignOut.add(callback);

  Future<void> signOut() async {
    _token = null;
    _user = null;

    for (final callback in _onSignOut) {
      callback();
    }

    notifyListeners();

    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
