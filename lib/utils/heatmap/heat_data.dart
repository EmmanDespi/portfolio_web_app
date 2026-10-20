import 'dart:async';
import 'dart:convert';

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'heat_models.dart';
import 'package:portfolio/utils/heatmap/ph_geo.dart';

// ═══════════════════════════════════════════════════════════
// Weather — Open-Meteo (free, no API key, CORS-enabled)
// ═══════════════════════════════════════════════════════════
class WeatherService {
  static const _host = 'api.open-meteo.com';
  static const _current = 'temperature_2m,relative_humidity_2m,apparent_temperature';

  /// One request for many points. Returns readings in the same order
  /// (null where a point had no usable data).
  Future<List<WeatherReading?>> fetchMany(List<GeoPoint> points) async {
    final uri = Uri.https(_host, '/v1/forecast', {
      'latitude': points.map((p) => p.lat.toStringAsFixed(3)).join(','),
      'longitude': points.map((p) => p.lon.toStringAsFixed(3)).join(','),
      'current': _current,
      'timezone': 'Asia/Manila',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw http.ClientException('Open-Meteo returned ${res.statusCode}');
    }
    final json = jsonDecode(res.body);
    // A single location comes back as an object, several as a list.
    final list = json is List ? json : [json];
    return [for (final item in list) _parse(item)];
  }

  /// Weather at one point; null on any failure.
  Future<WeatherReading?> fetchOne(double lat, double lon) async {
    try {
      final r = await fetchMany([GeoPoint(lat, lon)]);
      return r.isEmpty ? null : r.first;
    } catch (_) {
      return null;
    }
  }

  WeatherReading? _parse(dynamic json) {
    if (json is! Map) return null;
    final cur = json['current'];
    if (cur is! Map) return null;
    final t = cur['temperature_2m'];
    final h = cur['relative_humidity_2m'];
    final a = cur['apparent_temperature'];
    if (t is! num || h is! num) return null;
    return WeatherReading(
      tempC: t.toDouble(),
      humidity: h.toDouble(),
      apparentC: (a is num ? a : t).toDouble(),
      time: DateTime.tryParse('${cur['time']}'),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Detailed grid weather (for zoomed-in views)
// ═══════════════════════════════════════════════════════════
class GridReading {
  const GridReading(this.point, this.reading);
  final GeoPoint point;
  final WeatherReading reading;
}

/// Samples a fixed lattice so panning reuses cached cells.
class GridWeatherService {
  GridWeatherService(this._weather);
  final WeatherService _weather;

  final _cache = <String, ({DateTime at, WeatherReading r})>{};
  static const _ttl = Duration(minutes: 30);
  static const _maxPoints = 60;

  double stepFor(double zoom) {
    if (zoom >= 14) return 0.01;
    if (zoom >= 12) return 0.02;
    if (zoom >= 11) return 0.05;
    if (zoom >= 10) return 0.1;
    return 0.25;
  }

  Future<List<GridReading>> fetch(LatLngBounds b, double zoom) async {
    final step = stepFor(zoom);
    final cells = <(int, int)>[];
    for (var i = (b.south / step).floor(); i <= (b.north / step).ceil(); i++) {
      for (var j = (b.west / step).floor(); j <= (b.east / step).ceil(); j++) {
        cells.add((i, j));
      }
    }
    if (cells.length > _maxPoints) return const []; // too wide: zoom in

    String key(int i, int j) => '$step:$i:$j';
    final now = DateTime.now();
    final missing = [
      for (final c in cells)
        if (_cache[key(c.$1, c.$2)] == null ||
            now.difference(_cache[key(c.$1, c.$2)]!.at) > _ttl)
          c,
    ];

    if (missing.isNotEmpty) {
      final pts = [for (final c in missing) GeoPoint(c.$1 * step, c.$2 * step)];
      final res = await _weather.fetchMany(pts);
      for (var k = 0; k < missing.length && k < res.length; k++) {
        final r = res[k];
        if (r != null) {
          _cache[key(missing[k].$1, missing[k].$2)] = (at: now, r: r);
        }
      }
    }

    return [
      for (final c in cells)
        if (_cache[key(c.$1, c.$2)] != null)
          GridReading(
            GeoPoint(c.$1 * step, c.$2 * step),
            _cache[key(c.$1, c.$2)]!.r,
          ),
    ];
  }
}

// ═══════════════════════════════════════════════════════════
// Nearby places — OpenStreetMap via the Overpass API
// ═══════════════════════════════════════════════════════════
class PlacesService {
  /// Public Overpass servers; the next one is tried if one fails or is busy.
  static const _hosts = ['overpass-api.de', 'overpass.kumi.systems'];

  /// Small radii first so the nearest places are found before the result cap.
  static const _tiers = [500, 1500, 5000, 15000];

  /// Nearest place of each [PlaceKind], widening the search radius only for
  /// kinds that haven't been found yet.
  Future<NearbyResult> nearest(double lat, double lon) async {
    final found = <PlaceKind, Place>{};
    var failed = false;

    for (final radius in _tiers) {
      final kinds = [
        for (final k in PlaceKind.values)
          if (!found.containsKey(k) && radius <= k.maxRadiusM) k,
      ];
      if (kinds.isEmpty) break;

      try {
        final places = await _query(lat, lon, radius, kinds);
        for (final k in kinds) {
          final ofKind = places.where((p) => p.kind == k).toList()
            ..sort((a, b) => a.distanceM.compareTo(b.distanceM));
          if (ofKind.isNotEmpty) found[k] = ofKind.first;
        }
      } catch (_) {
        failed = true;
        break;
      }
    }
    return NearbyResult(nearest: found, failed: failed);
  }

  Future<http.Response> _post(String query) async {
    Object? last;
    for (final host in _hosts) {
      try {
        final res = await http
            .post(Uri.https(host, '/api/interpreter'), body: {'data': query})
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) return res;
        last = http.ClientException('$host returned ${res.statusCode}');
      } catch (e) {
        last = e;
      }
    }
    throw last ?? http.ClientException('Overpass unavailable');
  }

  Future<List<Place>> _query(
    double lat,
    double lon,
    int radius,
    List<PlaceKind> kinds,
  ) async {
    final parts = StringBuffer();
    for (final k in kinds) {
      for (final f in k.osmFilters) {
        parts.write('nwr$f(around:$radius,$lat,$lon);');
      }
    }
    final query = '[out:json][timeout:12];($parts);out center 300;';

    final res = await _post(query);

    final elements = (jsonDecode(res.body) as Map)['elements'] as List? ?? [];
    final out = <Place>[];
    for (final e in elements) {
      if (e is! Map) continue;
      final tags = (e['tags'] as Map?) ?? const {};
      final kind = _kindOf(tags);
      if (kind == null) continue;

      final center = e['center'] as Map?;
      final pLat = (e['lat'] ?? center?['lat']) as num?;
      final pLon = (e['lon'] ?? center?['lon']) as num?;
      if (pLat == null || pLon == null) continue;

      final rawName = tags['name'] ?? tags['brand'];
      final name = rawName is String ? rawName.trim() : null;
      out.add(
        Place(
          kind: kind,
          name: (name == null || name.isEmpty)
              ? 'Unnamed ${kind.label.toLowerCase()}'
              : name,
          lat: pLat.toDouble(),
          lon: pLon.toDouble(),
          distanceM: haversineM(lat, lon, pLat.toDouble(), pLon.toDouble()),
        ),
      );
    }
    return out;
  }

  PlaceKind? _kindOf(Map tags) {
    switch (tags['shop']) {
      case 'convenience':
        return PlaceKind.convenience;
      case 'supermarket':
        return PlaceKind.supermarket;
      case 'mall':
        return PlaceKind.mall;
    }
    switch (tags['amenity']) {
      case 'restaurant':
        return PlaceKind.restaurant;
      case 'fast_food':
        return PlaceKind.fastFood;
      case 'cafe':
        return PlaceKind.cafe;
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════
// Area name (barangay / city) — Nominatim reverse geocoding
// ═══════════════════════════════════════════════════════════
class GeocodeService {
  static const _host = 'nominatim.openstreetmap.org';
  final _cache = <String, String?>{};

  /// e.g. "Barangay X, Las Piñas, Metro Manila". Null if unknown/failed.
  Future<String?> reverse(double lat, double lon) async {
    final key = '${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)}';
    if (_cache.containsKey(key)) return _cache[key];
    try {
      final uri = Uri.https(_host, '/reverse', {
        'format': 'jsonv2',
        'lat': lat.toStringAsFixed(5),
        'lon': lon.toStringAsFixed(5),
        'zoom': '16',
        'addressdetails': '1',
        'accept-language': 'en',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      final addr = json is Map ? json['address'] : null;
      if (addr is! Map) return null;

      String? pick(List<String> keys) {
        for (final k in keys) {
          final v = addr[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final parts = <String>[];
      for (final v in [
        pick(['suburb', 'village', 'quarter', 'neighbourhood', 'hamlet']),
        pick(['city', 'town', 'municipality', 'city_district']),
        pick(['state', 'region', 'county']),
      ]) {
        if (v != null && !parts.contains(v)) parts.add(v);
      }
      final label = parts.isEmpty ? null : parts.join(', ');
      _cache[key] = label;
      return label;
    } catch (_) {
      return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Riverpod
// ═══════════════════════════════════════════════════════════
final weatherServiceProvider = Provider((ref) => WeatherService());
final placesServiceProvider = Provider((ref) => PlacesService());
final geocodeServiceProvider = Provider((ref) => GeocodeService());
final gridServiceProvider =
    Provider((ref) => GridWeatherService(ref.read(weatherServiceProvider)));

final phGeoProvider = FutureProvider<PhGeo>((ref) => PhGeo.load());

class ProvinceWeather {
  const ProvinceWeather({this.readings = const {}, this.error});
  final Map<String, WeatherReading> readings;
  final String? error;
}

/// Live weather for every province/city in one request.
/// Failures are returned as data (not thrown) so the UI can offer a retry.
final provinceWeatherProvider = FutureProvider<ProvinceWeather>((ref) async {
  final geo = await ref.watch(phGeoProvider.future);
  try {
    final points = [for (final p in geo.provinces) GeoPoint(p.lat, p.lon)];
    final readings = await ref.read(weatherServiceProvider).fetchMany(points);
    return ProvinceWeather(
      readings: {
        for (var i = 0; i < geo.provinces.length; i++)
          if (i < readings.length && readings[i] != null)
            geo.provinces[i].name: readings[i]!,
      },
    );
  } catch (_) {
    return const ProvinceWeather(
      error: 'Could not load live temperatures. Check your connection and retry.',
    );
  }
});

class HeatModeNotifier extends Notifier<HeatMode> {
  @override
  HeatMode build() => HeatMode.heatIndex;

  void set(HeatMode mode) => state = mode;
}

final heatModeProvider =
    NotifierProvider<HeatModeNotifier, HeatMode>(HeatModeNotifier.new);

class SelectionNotifier extends Notifier<Selection?> {
  @override
  Selection? build() => null;

  void select(Selection s) => state = s;
  void clear() => state = null;
}

final selectionProvider =
    NotifierProvider<SelectionNotifier, Selection?>(SelectionNotifier.new);

/// Exact weather at the tapped point.
final pointWeatherProvider =
    FutureProvider.autoDispose<WeatherReading?>((ref) async {
  final sel = ref.watch(selectionProvider);
  if (sel == null) return null;
  return ref.read(weatherServiceProvider).fetchOne(sel.lat, sel.lon);
});

/// Nearest store / mall / café / water point to the tapped point.
/// Debounced so rapid taps don't hammer the public Overpass server.
final nearbyProvider = FutureProvider.autoDispose<NearbyResult?>((ref) async {
  final sel = ref.watch(selectionProvider);
  if (sel == null) return null;

  var disposed = false;
  ref.onDispose(() => disposed = true);
  await Future<void>.delayed(const Duration(milliseconds: 600));
  if (disposed) return null;

  return ref.read(placesServiceProvider).nearest(sel.lat, sel.lon);
});

/// Barangay / city name for the tapped point.
/// Debounced: Nominatim allows at most 1 request per second.
final areaNameProvider = FutureProvider.autoDispose<String?>((ref) async {
  final sel = ref.watch(selectionProvider);
  if (sel == null) return null;

  var disposed = false;
  ref.onDispose(() => disposed = true);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  if (disposed) return null;

  return ref.read(geocodeServiceProvider).reverse(sel.lat, sel.lon);
});

// ── Map viewport + detailed grid ─────────────────────────

/// Named MapViewport to avoid clashing with Flutter's `Viewport` widget.
class MapViewport {
  const MapViewport(this.bounds, this.zoom);
  final LatLngBounds bounds;
  final double zoom;
}

class ViewportNotifier extends Notifier<MapViewport?> {
  @override
  MapViewport? build() => null;

  void set(MapViewport v) => state = v;
}

final viewportProvider =
    NotifierProvider<ViewportNotifier, MapViewport?>(ViewportNotifier.new);

/// Detailed readings for the visible area; only active when zoomed in.
final gridWeatherProvider =
    FutureProvider.autoDispose<List<GridReading>>((ref) async {
  final vp = ref.watch(viewportProvider);
  if (vp == null || vp.zoom < 8) return const [];

  var disposed = false;
  ref.onDispose(() => disposed = true);
  await Future<void>.delayed(const Duration(milliseconds: 600)); // debounce
  if (disposed) return const [];

  try {
    return await ref.read(gridServiceProvider).fetch(vp.bounds, vp.zoom);
  } catch (_) {
    return const [];
  }
});