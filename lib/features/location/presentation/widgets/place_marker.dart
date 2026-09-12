import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../data/place_models.dart';

/// A name for a circle.
///
/// The circle alone says "something is here" and not what. A tinted pill with
/// the kind's glyph and the place's name answers it without a tap, which is
/// the whole standard a map marker has to meet.
///
/// ## Why the icon is painted as text
///
/// [IconData] is a codepoint in a font, not an image. Drawing one onto a
/// canvas means laying it out as a single character in its own font family —
/// which is exactly what [Icon] does internally. Going through the same route
/// keeps these glyphs identical to the ones in the sheet that created them.
///
/// The `package` argument is the part that is easy to miss: Material icons
/// ship inside the Flutter package, and omitting it renders every icon as a
/// tofu box in release builds while working perfectly in debug.
class PlaceMarker {
  const PlaceMarker._();

  static final Map<String, BitmapDescriptor> _cache = {};
  static final Map<String, Future<BitmapDescriptor>> _building = {};

  static String cacheKey(FamilyPlace place, double pixelRatio) =>
      '${place.name}|${place.kind}|$pixelRatio';

  static BitmapDescriptor? cached(String key) => _cache[key];

  /// Anchored at the bottom centre: the pill sits *above* the circle's
  /// centre point rather than over it, so the centre stays visible and a
  /// place under a person's marker does not hide them.
  static const Offset anchor = Offset(0.5, 1.0);

  static Future<BitmapDescriptor> forPlace(
    FamilyPlace place, {
    double pixelRatio = 3.0,
  }) {
    final key = cacheKey(place, pixelRatio);

    final cached = _cache[key];

    if (cached != null) return Future.value(cached);

    return _building[key] ??=
        _build(key, place, pixelRatio).whenComplete(() => _building.remove(key));
  }

  static Future<BitmapDescriptor> _build(
    String key,
    FamilyPlace place,
    double scale,
  ) async {
    final tint = place.tint;

    const height = 30.0;
    const padX = 9.0;
    const iconSize = 14.0;
    const gap = 6.0;

    final label = TextPainter(
      text: TextSpan(
        text: place.name,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12 * scale,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 140 * scale);

    final glyph = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(place.icon.codePoint),
        style: TextStyle(
          fontSize: iconSize * scale,
          fontFamily: place.icon.fontFamily,
          package: place.icon.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final width =
        padX * 2 * scale + glyph.width + gap * scale + label.width;

    // Room under the pill for the little tail that points at the centre.
    const tail = 6.0;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, width, height * scale),
      Radius.circular(height / 2 * scale),
    );

    canvas.drawRRect(
      body.shift(Offset(0, 1.5 * scale)),
      Paint()
        ..color = const Color(0xFF0E1B2A).withValues(alpha: 0.28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * scale),
    );

    canvas.drawRRect(body, Paint()..color = tint);

    // A hairline of white inside the edge, so the pill separates from a road
    // of a similar colour — parks are green and so is the `park` kind.
    canvas.drawRRect(
      body.deflate(0.75 * scale),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * scale
        ..color = Colors.white.withValues(alpha: 0.35),
    );

    final tailPath = Path()
      ..moveTo(width / 2 - 5 * scale, height * scale - scale)
      ..lineTo(width / 2, (height + tail) * scale)
      ..lineTo(width / 2 + 5 * scale, height * scale - scale)
      ..close();

    canvas.drawPath(tailPath, Paint()..color = tint);

    glyph.paint(
      canvas,
      Offset(padX * scale, (height * scale - glyph.height) / 2),
    );

    label.paint(
      canvas,
      Offset(
        padX * scale + glyph.width + gap * scale,
        (height * scale - label.height) / 2,
      ),
    );

    final image = await recorder.endRecording().toImage(
          width.ceil(),
          ((height + tail) * scale).ceil(),
        );

    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final descriptor = BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: scale,
    );

    _cache[key] = descriptor;

    return descriptor;
  }

  /// Roughly how far a circle of this radius reaches on screen, in zoom
  /// levels — used to decide whether a place is worth labelling at all.
  ///
  /// A map of the whole city covered in pills for every circle in it is
  /// noise; the circles themselves still draw, and the name appears once you
  /// are close enough for it to mean something.
  static bool labelVisibleAt(double zoom, double radiusMetres) {
    // Metres per pixel at the equator, halving per zoom level. The latitude
    // correction is omitted deliberately — this is a legibility threshold,
    // not a measurement, and being 20% out near the poles changes nothing.
    final metresPerPixel = 156543.03392 / math.pow(2, zoom);

    // Show the name once the circle is at least 40 px across.
    return (radiusMetres * 2) / metresPerPixel >= 40;
  }

  static void clear() {
    _cache.clear();
    _building.clear();
  }
}
