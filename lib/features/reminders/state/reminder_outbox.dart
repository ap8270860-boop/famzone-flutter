import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Answers given to a notification, held on disk until the server hears them.
///
/// This exists because of where the tap happens. Somebody presses **Done** on
/// a medicine reminder from their lock screen, in a lift, with the app not
/// running. Three things are true at that moment and all three are awkward:
///
///  - **The app may be dead.** Android hands the tap to a *separate background
///    isolate* with its own memory. It cannot see the store, the session token
///    or anything else the running app knows.
///  - **There may be no network.** Posting straight to the server is a coin
///    flip, and a lost "Done" is a dose that looks missed in somebody's
///    medicine history.
///  - **It has to be fast.** The isolate is killed shortly after the handler
///    returns, so there is no waiting on a request.
///
/// So the handler does the only thing that is always safe: appends one line to
/// a file. The app drains that file the next time it is alive and online.
///
/// A file and not shared_preferences — path_provider is already a dependency,
/// and appending is a better fit than read-modify-write for something two
/// isolates touch.
class ReminderOutbox {
  const ReminderOutbox._();

  static const String _fileName = 'reminder_outbox.jsonl';

  /// Where entries are moved before being read.
  ///
  /// The rename is what makes draining safe. Reading the live file and then
  /// deleting it loses anything the background isolate appended in between —
  /// which is precisely the tap somebody made while the app was starting up.
  /// A rename is atomic on both platforms, so the drain works on a file
  /// nothing can still be writing to, and new answers land in a fresh one.
  static const String _drainingName = 'reminder_outbox.draining.jsonl';

  /// Anything older than this is dropped rather than sent.
  ///
  /// A "Done" surfacing three weeks late is not a correction, it is noise —
  /// and by then the nightly close-out has long since written the day off. The
  /// window is generous enough to cover a holiday with the phone off.
  static const Duration maxAge = Duration(days: 7);

  static Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();

    return File('${dir.path}/$name');
  }

  /// Record one answer. Safe to call from a background isolate.
  ///
  /// Never throws. A failure here is invisible to the person who tapped, and
  /// the alternative — an exception inside a background handler — takes the
  /// whole isolate down and loses the entry anyway.
  static Future<void> add({
    required String reminderId,
    required DateTime dueAt,
    required String status,
  }) async {
    try {
      final line = jsonEncode({
        'reminder_id': reminderId,
        'due_at': dueAt.toUtc().toIso8601String(),
        'status': status,
        'tapped_at': DateTime.now().toUtc().toIso8601String(),
      });

      final file = await _file(_fileName);

      await file.writeAsString(
        '$line\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      debugPrint('reminder outbox write failed: $e');
    }
  }

  /// Take everything pending, leaving the outbox empty.
  ///
  /// Returns entries oldest first. Anything stale or unparseable is dropped
  /// here rather than handed on — a corrupted line must not wedge the queue
  /// forever, which is what happens when a drain refuses to make progress
  /// past something it cannot read.
  static Future<List<OutboxEntry>> drain() async {
    try {
      final live = await _file(_fileName);

      if (!await live.exists()) return const [];

      final draining = await _file(_drainingName);

      /*
       | A leftover draining file means the app died mid-drain last time.
       |
       | Its contents are still unsent, so they are folded back in rather than
       | overwritten — losing them here would be losing exactly the answers
       | that were already at risk.
       */
      if (await draining.exists()) {
        final carried = await draining.readAsString();

        await live.writeAsString(carried, mode: FileMode.append, flush: true);
        await draining.delete();
      }

      await live.rename(draining.path);

      final text = await draining.readAsString();

      await draining.delete();

      final cutoff = DateTime.now().toUtc().subtract(maxAge);
      final out = <OutboxEntry>[];

      for (final line in const LineSplitter().convert(text)) {
        if (line.trim().isEmpty) continue;

        final entry = OutboxEntry.tryParse(line);

        if (entry == null) continue;
        if (entry.tappedAt.isBefore(cutoff)) continue;

        out.add(entry);
      }

      return out;
    } on MissingPluginException {
      // The background isolate has no plugin registrant. Nothing to drain,
      // and nothing worth shouting about.
      return const [];
    } catch (e) {
      debugPrint('reminder outbox drain failed: $e');

      return const [];
    }
  }

  /// Put entries back after a failed send.
  ///
  /// Appended rather than prepended: order within a single occurrence does not
  /// matter because the server keys on (reminder, due_at) and the last write
  /// wins, and appending cannot clobber anything the background isolate added
  /// while the request was in flight.
  static Future<void> restore(List<OutboxEntry> entries) async {
    if (entries.isEmpty) return;

    try {
      final file = await _file(_fileName);

      await file.writeAsString(
        entries.map((e) => jsonEncode(e.toJson())).join('\n') + '\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (e) {
      debugPrint('reminder outbox restore failed: $e');
    }
  }
}

/// One answer waiting to be sent.
@immutable
class OutboxEntry {
  const OutboxEntry({
    required this.reminderId,
    required this.dueAt,
    required this.status,
    required this.tappedAt,
  });

  final String reminderId;
  final DateTime dueAt;

  /// done | snoozed | skipped
  final String status;

  /// When the person actually pressed it — not when we got round to sending
  /// it. Used to age entries out, and the honest answer to "when was this
  /// taken" if that is ever surfaced.
  final DateTime tappedAt;

  Map<String, dynamic> toJson() => {
        'reminder_id': reminderId,
        'due_at': dueAt.toUtc().toIso8601String(),
        'status': status,
        'tapped_at': tappedAt.toUtc().toIso8601String(),
      };

  static OutboxEntry? tryParse(String line) {
    try {
      final json = jsonDecode(line);

      if (json is! Map<String, dynamic>) return null;

      final id = json['reminder_id'] as String?;
      final due = DateTime.tryParse(json['due_at'] as String? ?? '');
      final status = json['status'] as String?;

      if (id == null || id.isEmpty || due == null || status == null) {
        return null;
      }

      return OutboxEntry(
        reminderId: id,
        dueAt: due,
        status: status,
        tappedAt: DateTime.tryParse(json['tapped_at'] as String? ?? '') ??
            DateTime.now().toUtc(),
      );
    } catch (_) {
      return null;
    }
  }
}
