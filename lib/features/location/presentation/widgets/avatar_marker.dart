import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../../../../core/theme/app_colors.dart';

/// People-shaped map markers.
///
/// Google's default pin is a red teardrop, and a map of six identical red
/// teardrops answers none of the questions anybody opens a family map to ask.
/// Drawing the person's face into the pin means the map is readable at a
/// glance without tapping anything, which is the entire difference between a
/// map you consult and a map you use.
///
/// Everything here is painted once and cached. A marker rebuilt on every
/// position update would mean decoding a PNG sixty times a second, and the
/// resulting jank would undo all the interpolation work it sits next to.
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

  /// The marker's drawn size in logical pixels, before device scaling.
  static const double _size = 54;

  /// Room under the circle for the pointer.
  static const double _tail = 10;

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
    bool stale = false,
    bool isMe = false,
    double pixelRatio = 3.0,
  }) {
    final key = '$userId|${avatarUrl ?? ''}|$stale|$isMe|$pixelRatio';

    final cached = _cache[key];

    if (cached != null) return Future.value(cached);

    return _building[key] ??= _build(
      key: key,
      initials: initials,
      avatarUrl: avatarUrl,
      stale: stale,
      isMe: isMe,
      pixelRatio: pixelRatio,
    ).whenComplete(() => _building.remove(key));
  }

  static Future<BitmapDescriptor> _build({
    required String key,
    required String initials,
    required String? avatarUrl,
    required bool stale,
    required bool isMe,
    required double pixelRatio,
  }) async {
    final photo = await _photo(avatarUrl);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final scale = pixelRatio;
    final width = _size * scale;
    final height = (_size + _tail) * scale;
    final radius = width / 2;
    final centre = Offset(radius, radius);

    // --- the shadow, so a pin over pale water still reads ------------------

    canvas.drawCircle(
      centre.translate(0, 2 * scale),
      radius - 1 * scale,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * scale),
    );

    // --- the pointer ------------------------------------------------------

    final tailPaint = Paint()
      ..shader = _ring(isMe, stale).createShader(
        Rect.fromCircle(center: centre, radius: radius),
      );

    final tail = Path()
      ..moveTo(radius - 7 * scale, height - _tail * scale - 2 * scale)
      ..lineTo(radius, height - 1 * scale)
      ..lineTo(radius + 7 * scale, height - _tail * scale - 2 * scale)
      ..close();

    canvas.drawPath(tail, tailPaint);

    // --- the ring ---------------------------------------------------------

    canvas.drawCircle(centre, radius - 1 * scale, tailPaint);

    // --- the face ---------------------------------------------------------

    final inner = radius - 4.5 * scale;

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: centre, radius: inner)));

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
      canvas.drawCircle(
        centre,
        inner,
        Paint()..color = AppColors.royalNavy,
      );

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

      label.paint(
        canvas,
        centre - Offset(label.width / 2, label.height / 2),
      );
    }

    if (stale) {
      // Drawn over the face rather than by fading the whole marker: a
      // half-transparent pin disappears against water, and the point is to
      // say "this is old", not "this is barely here".
      canvas.drawCircle(
        centre,
        inner,
        Paint()..color = AppColors.deepNavy.withValues(alpha: 0.55),
      );
    }

    canvas.restore();

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

  /// The ring colour, which is also the marker's whole visual language.
  ///
  /// Brand gradient for me, mint for a live family member, muted grey once a
  /// position has gone stale. Three states, distinguishable without reading
  /// anything — which is what a map is for.
  static LinearGradient _ring(bool isMe, bool stale) {
    if (stale) {
      return const LinearGradient(
        colors: [Color(0xFF4A5570), Color(0xFF39415A)],
      );
    }

    if (isMe) return AppColors.brandGradient;

    return const LinearGradient(
      colors: [AppColors.mint, AppColors.aqua],
    );
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
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 8));

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
  }
}
