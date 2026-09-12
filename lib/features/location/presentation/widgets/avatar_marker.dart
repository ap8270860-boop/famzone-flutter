import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// People-shaped map markers.
///
/// Google's default pin is a red teardrop, and a map of six identical red
/// teardrops answers none of the questions anybody opens a family map to ask.
/// Drawing the person's face into the pin means the map is readable at a
/// glance without tapping anything, which is the entire difference between a
/// map you consult and a map you use.
///
/// The marker is one bitmap — circle, pointer and the little label card under
/// it are all painted together, because Google Maps has no concept of a
/// marker with a widget attached. That constraint is what drives the caching
/// rules below: every distinct appearance is a separate bitmap, so anything
/// that varies continuously has to be quantised before it reaches the label,
/// or the map repaints faces at sixty frames a second and every bit of the
/// interpolation work next door is wasted.
class AvatarMarker {
  const AvatarMarker._();

  /// Painted markers, keyed by everything that changes their appearance.
  static final Map<String, BitmapDescriptor> _cache = {};

  /// Avatars already fetched and decoded, so six markers of the same person
  /// across a session cost one download.
  static final Map<String, ui.Image?> _photos = {};

  /// In-flight builds, so a burst of position updates for a person whose
  /// marker is still being painted does not start five more paints.
  static final Map<String, Future<BitmapDescriptor>> _building = {};

  /// The face's drawn diameter in logical pixels, before device scaling.
  static const double _circle = 52;

  /// The pointer below it. Its tip is the marker's actual position.
  static const double _tail = 9;

  /// Gap between the pointer's tip and the top of the label card.
  static const double _gap = 5;

  static const double _labelRadius = 8;

  /// One person's marker.
  ///
  /// [stale] dims it, which is how a position that has stopped updating
  /// announces itself without being removed — knowing where somebody was
  /// twenty minutes ago is still worth showing, as long as the map is honest
  /// that it is twenty minutes old.
  static Future<BitmapDescriptor> forPerson({
    required String userId,
    required String initials,
    String? avatarUrl,
    String? name,
    String? caption,
    Color ring = const Color(0xFF2BE07F),
    bool stale = false,
    bool isMe = false,
    int unread = 0,
    double pixelRatio = 3.0,
  }) {
    final key = cacheKey(
      userId: userId,
      avatarUrl: avatarUrl,
      name: name,
      caption: caption,
      ring: ring,
      stale: stale,
      isMe: isMe,
      unread: unread,
      pixelRatio: pixelRatio,
    );

    final cached = _cache[key];

    if (cached != null) return Future.value(cached);

    // isMe is part of the key but not of the painting: the ring colour
    // arrives already decided, because which green means "me" is a property
    // of the map's palette rather than of the marker.
    return _building[key] ??= _build(
      key: key,
      initials: initials,
      avatarUrl: avatarUrl,
      name: name,
      caption: caption,
      ring: ring,
      stale: stale,
      unread: unread,
      pixelRatio: pixelRatio,
    ).whenComplete(() => _building.remove(key));
  }

  /// The key a given appearance will be cached under.
  ///
  /// Public because the map screen needs to ask "is this marker already
  /// painted" synchronously, while building its marker set inside a frame.
  /// Awaiting [forPerson] there would mean a frame with no markers on it.
  static String cacheKey({
    required String userId,
    String? avatarUrl,
    String? name,
    String? caption,
    Color ring = const Color(0xFF2BE07F),
    bool stale = false,
    bool isMe = false,
    int unread = 0,
    double pixelRatio = 3.0,
  }) =>
      '$userId|${avatarUrl ?? ''}|${name ?? ''}|${caption ?? ''}'
      '|${ring.toARGB32()}|$stale|$isMe|$unread|$pixelRatio';

  static BitmapDescriptor? cached(String key) => _cache[key];

  /// Where the marker's point sits inside its own bitmap.
  ///
  /// Not `(0.5, 1.0)`. That is right for a bare pin, but this bitmap carries
  /// a label card *below* the pointer, so anchoring at the bottom would hang
  /// everybody a label's height north of where they actually are — a
  /// twenty-metre error at street zoom, which on a safety app is the
  /// difference between "outside the school" and "inside it".
  static Offset anchorFor({bool labelled = true}) {
    if (!labelled) return const Offset(0.5, 1.0);

    final total = _circle + _tail + _gap + _labelHeight;

    return Offset(0.5, (_circle + _tail) / total);
  }

  static const double _labelHeight = 38;

  /*
  |----------------------------------------------------------------------------
  | Distance, quantised
  |----------------------------------------------------------------------------
  */

  /// A distance rounded hard enough that the label stops changing.
  ///
  /// Raw metres would give a new string — and therefore a fresh bitmap
  /// decode — on every single fix. Bucketing to 50 m under a kilometre and
  /// 100 m over it means a walking family member repaints their own marker
  /// about once a minute, and nobody can tell the label is approximate
  /// because at these distances it always was.
  static String? distanceLabel(double? metres) {
    if (metres == null) return null;

    if (metres < 1000) {
      final rounded = (metres / 50).round() * 50;

      return rounded <= 0 ? 'Here' : '$rounded m';
    }

    final km = (metres / 100).round() / 10;

    if (km >= 100) return '${km.round()} km';

    return '${km.toStringAsFixed(1)} km';
  }

  /*
  |----------------------------------------------------------------------------
  | Painting
  |----------------------------------------------------------------------------
  */

  static Future<BitmapDescriptor> _build({
    required String key,
    required String initials,
    required String? avatarUrl,
    required String? name,
    required String? caption,
    required Color ring,
    required bool stale,
    required int unread,
    required double pixelRatio,
  }) async {
    final photo = await _photo(avatarUrl);

    final scale = pixelRatio;
    final labelled = name != null && name.isNotEmpty;

    final accent = stale ? const Color(0xFF9AA5B5) : ring;

    // --- measure the label first, because it decides the bitmap's width ----

    final title = labelled
        ? (TextPainter(
            text: TextSpan(
              text: name,
              style: TextStyle(
                color: const Color(0xFF1B2430),
                fontSize: 12 * scale,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: 128 * scale))
        : null;

    final sub = (labelled && caption != null && caption.isNotEmpty)
        ? (TextPainter(
            text: TextSpan(
              text: caption,
              style: TextStyle(
                color: const Color(0xFF69748A),
                fontSize: 10.5 * scale,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            ellipsis: '…',
          )..layout(maxWidth: 128 * scale))
        : null;

    const labelPadX = 9.0;

    final labelWidth = title == null
        ? 0.0
        : math.max(title.width, sub?.width ?? 0) + labelPadX * 2 * scale;

    final circle = _circle * scale;
    final width = math.max(circle, labelWidth);
    final height =
        (labelled ? _circle + _tail + _gap + _labelHeight : _circle + _tail) *
            scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final radius = circle / 2;
    final centre = Offset(width / 2, radius);
    final tipY = (_circle + _tail) * scale;

    // --- shadow, so a marker over pale road or water still reads -----------

    canvas.drawCircle(
      centre.translate(0, 2.5 * scale),
      radius - scale,
      Paint()
        ..color = const Color(0xFF0E1B2A).withValues(alpha: 0.30)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * scale),
    );

    // --- the pointer ------------------------------------------------------
    //
    // Painted before the circle so the joint is hidden behind it. Drawn in
    // the ring colour rather than white, because on a light map a white
    // pointer on a white road disappears and the marker appears to float.

    final pointer = Path()
      ..moveTo(centre.dx - 7 * scale, radius + circle * 0.30)
      ..lineTo(centre.dx, tipY)
      ..lineTo(centre.dx + 7 * scale, radius + circle * 0.30)
      ..close();

    canvas.drawPath(
      pointer,
      Paint()
        ..color = const Color(0xFF0E1B2A).withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * scale),
    );

    canvas.drawPath(pointer, Paint()..color = accent);

    // --- the ring ---------------------------------------------------------
    //
    // Two rings, not one: a white collar inside the coloured edge. On a
    // light map a coloured ring sitting straight against a photograph reads
    // as a coloured halo around a face; the white gap is what makes it read
    // as a *badge*, which is the same trick every map app uses.

    canvas.drawCircle(centre, radius - scale, Paint()..color = accent);
    canvas.drawCircle(
      centre,
      radius - 3.5 * scale,
      Paint()..color = Colors.white,
    );

    // --- the face ---------------------------------------------------------

    final inner = radius - 5.5 * scale;

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: centre, radius: inner)),
    );

    if (photo != null) {
      // Cover, not fit: a portrait avatar letterboxed inside a circle looks
      // like a mistake, and cropping a face to a circle is what every other
      // app does because it works.
      final side = math.min(photo.width, photo.height).toDouble();

      canvas.drawImageRect(
        photo,
        Rect.fromLTWH(
          (photo.width - side) / 2,
          (photo.height - side) / 2,
          side,
          side,
        ),
        Rect.fromCircle(center: centre, radius: inner),
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      canvas.drawCircle(centre, inner, Paint()..color = accent);

      final label = TextPainter(
        text: TextSpan(
          text: initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: 17 * scale,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      label.paint(canvas, centre - Offset(label.width / 2, label.height / 2));
    }

    if (stale) {
      // Drawn over the face rather than by fading the whole marker: a
      // half-transparent pin disappears against water, and the point is to
      // say "this is old", not "this is barely here".
      canvas.drawCircle(
        centre,
        inner,
        Paint()..color = const Color(0xFFE8ECF2).withValues(alpha: 0.62),
      );
    }

    canvas.restore();

    /*
     | The unread badge, over the ring's top-right.
     |
     | Static, unlike the one on the member card below the map, and that is a
     | constraint rather than a choice: a Google Maps marker is a bitmap, so
     | animating it would mean pushing a new PNG across the platform channel
     | every frame. The card animates; the marker states.
     |
     | Part of the cache key, so a message arriving repaints this face once.
     | That is fine at the rate messages actually arrive, and it is exactly
     | why the *distance* in the label is bucketed to 50 m — the two together
     | must not turn into a repaint per fix.
     */
    if (unread > 0) {
      final label = unread > 9 ? '9+' : '$unread';

      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10 * scale,
            fontWeight: FontWeight.w800,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeRadius = math.max(8.0 * scale, text.width / 2 + 4.5 * scale);

      // Pushed onto the ring rather than outside the bitmap: the marker's
      // width is already decided by the label card, and growing it here
      // would shift the anchor and move everybody sideways.
      final badgeCentre = Offset(
        centre.dx + radius * 0.72,
        centre.dy - radius * 0.72,
      );

      canvas.drawCircle(
        badgeCentre,
        badgeRadius + 2 * scale,
        Paint()..color = Colors.white,
      );

      canvas.drawCircle(
        badgeCentre,
        badgeRadius,
        Paint()..color = const Color(0xFFE5484D),
      );

      text.paint(
        canvas,
        badgeCentre - Offset(text.width / 2, text.height / 2),
      );
    }

    // --- the label card ---------------------------------------------------

    if (title != null) {
      final top = tipY + _gap * scale;

      final card = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          (width - labelWidth) / 2,
          top,
          labelWidth,
          _labelHeight * scale,
        ),
        Radius.circular(_labelRadius * scale),
      );

      canvas.drawRRect(
        card.shift(Offset(0, 1.5 * scale)),
        Paint()
          ..color = const Color(0xFF0E1B2A).withValues(alpha: 0.22)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * scale),
      );

      canvas.drawRRect(card, Paint()..color = Colors.white);

      final textTop = sub == null
          ? top + (_labelHeight * scale - title.height) / 2
          : top +
              (_labelHeight * scale - title.height - sub.height - 2 * scale) /
                  2;

      title.paint(canvas, Offset((width - title.width) / 2, textTop));

      sub?.paint(
        canvas,
        Offset(
          (width - sub.width) / 2,
          textTop + title.height + 2 * scale,
        ),
      );
    }

    final image = await recorder.endRecording().toImage(
          width.ceil(),
          height.ceil(),
        );

    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final descriptor = BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: scale,
    );

    _cache[key] = descriptor;

    return descriptor;
  }

  /*
  |----------------------------------------------------------------------------
  | Photos
  |----------------------------------------------------------------------------
  */

  static Future<ui.Image?> _photo(String? url) async {
    if (url == null || url.isEmpty) return null;

    if (_photos.containsKey(url)) return _photos[url];

    try {
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return _photos[url] = null;

      // Decoded at marker size rather than full resolution. A 1600px avatar
      // scaled down by the GPU on every frame is a waste of both memory and
      // fill rate for something drawn 48 pixels across.
      final codec = await ui.instantiateImageCodec(
        response.bodyBytes,
        targetWidth: 160,
        targetHeight: 160,
      );

      final frame = await codec.getNextFrame();

      return _photos[url] = frame.image;
    } catch (_) {
      // A missing photo is a marker with initials in it, not an error.
      return _photos[url] = null;
    }
  }

  /// Forget everything. Called on sign-out, so the next account does not
  /// inherit the last one's faces.
  static void clear() {
    _cache.clear();
    _photos.clear();
    _building.clear();
  }
}
