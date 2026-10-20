import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart' show LatLng;

/// One province or city. All coordinates are in "geo units":
/// x = (lon - minLon) * cos(midLat), y = maxLat - lat.
class Province {
  Province._({
    required this.name,
    required this.region,
    required this.lon,
    required this.lat,
    required this.anchor,
    required this.polygons,
    required this.latLngPolygons,
    required this.path,
    required this.bounds,
    required this.area,
  });

  final String name;
  final String region;

  /// A point guaranteed to be inside the province (used for weather + labels).
  final double lon;
  final double lat;
  final Offset anchor;

  final List<List<Offset>> polygons;

  /// Same rings as [polygons], but as real lat/lon for flutter_map.
  final List<List<LatLng>> latLngPolygons;
  final Path path;
  final Rect bounds;
  final double area;

  bool contains(Offset g) {
    if (!bounds.contains(g)) return false;
    for (final poly in polygons) {
      if (_inPolygon(g, poly)) return true;
    }
    return false;
  }

  static bool _inPolygon(Offset p, List<Offset> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final a = poly[i];
      final b = poly[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }
}

class GeoPoint {
  const GeoPoint(this.lat, this.lon);
  final double lat;
  final double lon;
}

/// How the geo-unit map is fitted into a canvas of a given size.
/// (No longer used by the flutter_map view; kept for reference.)
class MapFrame {
  MapFrame(PhGeo geo, Size size) : this._(geo, size, _fitFor(geo, size));

  MapFrame._(PhGeo geo, Size size, this.fit)
      : origin = Offset(
          (size.width - geo.width * fit) / 2,
          (size.height - geo.height * fit) / 2,
        );

  static double _fitFor(PhGeo geo, Size size) =>
      math.min(size.width / geo.width, size.height / geo.height) * 0.94;

  /// Canvas pixels per geo unit.
  final double fit;
  final Offset origin;

  Offset toCanvas(Offset geoPoint) => origin + geoPoint * fit;
  Offset toGeo(Offset canvasPoint) => (canvasPoint - origin) / fit;
}

class PhGeo {
  PhGeo._(
    this.provinces,
    this.minLon,
    this.minLat,
    this.maxLon,
    this.maxLat,
    this.kx,
  );

  /// Sorted large → small so small areas (cities inside provinces) paint on top.
  final List<Province> provinces;
  final double minLon, minLat, maxLon, maxLat;
  final double kx;

  double get width => (maxLon - minLon) * kx;
  double get height => maxLat - minLat;

  Offset project(double lon, double lat) =>
      Offset((lon - minLon) * kx, maxLat - lat);

  GeoPoint unproject(Offset g) =>
      GeoPoint(maxLat - g.dy, g.dx / kx + minLon);

  /// Smallest province containing [g], or null (sea).
  Province? hit(Offset g) {
    for (var i = provinces.length - 1; i >= 0; i--) {
      if (provinces[i].contains(g)) return provinces[i];
    }
    return null;
  }

  static Future<PhGeo> load() async {
    final raw = jsonDecode(
      await rootBundle.loadString('assets/data/ph_provinces.json'),
    ) as Map<String, dynamic>;

    final b = (raw['bounds'] as List)
        .map((e) => (e as num).toDouble())
        .toList(growable: false);
    final minLon = b[0], minLat = b[1], maxLon = b[2], maxLat = b[3];
    final kx = math.cos(((minLat + maxLat) / 2) * math.pi / 180);

    Offset proj(double lon, double lat) =>
        Offset((lon - minLon) * kx, maxLat - lat);

    final provinces = <Province>[];
    for (final item in raw['provinces'] as List) {
      final m = item as Map<String, dynamic>;
      final polygons = <List<Offset>>[];
      final latLngPolys = <List<LatLng>>[];
      final path = Path();
      var area = 0.0;

      for (final flat in m['p'] as List) {
        final nums = (flat as List)
            .map((e) => (e as num).toDouble())
            .toList(growable: false);
        final pts = <Offset>[
          for (var i = 0; i + 1 < nums.length; i += 2)
            proj(nums[i], nums[i + 1]),
        ];
        polygons.add(pts);
        path.addPolygon(pts, true);

        // nums = [lon, lat, lon, lat, ...]
        latLngPolys.add([
          for (var i = 0; i + 1 < nums.length; i += 2)
            LatLng(nums[i + 1], nums[i]),
        ]);

        var a = 0.0;
        for (var i = 0, j = pts.length - 1; i < pts.length; j = i++) {
          a += (pts[j].dx + pts[i].dx) * (pts[j].dy - pts[i].dy);
        }
        area += a.abs() / 2;
      }

      final c = (m['c'] as List).map((e) => (e as num).toDouble()).toList();
      provinces.add(
        Province._(
          name: m['n'] as String,
          region: (m['r'] as String?) ?? '',
          lon: c[0],
          lat: c[1],
          anchor: proj(c[0], c[1]),
          polygons: polygons,
          latLngPolygons: latLngPolys,
          path: path,
          bounds: path.getBounds(),
          area: area,
        ),
      );
    }

    provinces.sort((a, b) => b.area.compareTo(a.area));
    return PhGeo._(provinces, minLon, minLat, maxLon, maxLat, kx);
  }
}