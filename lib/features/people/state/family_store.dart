import 'package:flutter/foundation.dart';

import '../../../core/session/session.dart';
import '../data/people_api.dart';
import '../data/people_models.dart';

/// The signed-in user's family circle.
///
/// Shared rather than local to the home screen, because accepting an invite
/// from the notifications screen has to move the family strip too — and those
/// two screens never see each other.
class FamilyStore extends ChangeNotifier {
  FamilyStore._();

  static final FamilyStore instance = FamilyStore._();

  final PeopleApi _api = PeopleApi();

  List<FamilyPerson> _members = const [];
  int _pendingReceived = 0;
  bool _loading = false;
  bool _loaded = false;

  List<FamilyPerson> get members => _members;
  int get pendingReceived => _pendingReceived;

  /// Only true before the first successful load, so a refresh never blanks the
  /// strip out.
  bool get loading => _loading && !_loaded;

  bool get isEmpty => _loaded && _members.isEmpty;

  Future<void> load() async {
    if (!Session.instance.isAuthenticated || _loading) return;

    _loading = true;

    try {
      final res = await _api.family();

      if (res.success) {
        _members = (res.dataMap['members'] as List?)
                ?.whereType<Map<String, dynamic>>()
                .map(FamilyPerson.fromJson)
                .toList() ??
            const [];

        _pendingReceived = res.dataMap['pending_received'] as int? ?? 0;
        _loaded = true;
      }
    } catch (_) {
      // Keep whatever is on screen. A failed refresh is not worth an error.
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void clear() {
    _members = const [];
    _pendingReceived = 0;
    _loaded = false;
    notifyListeners();
  }
}
