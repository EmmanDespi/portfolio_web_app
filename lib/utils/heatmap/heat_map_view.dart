import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart'
    show Geolocator, LocationAccuracy, LocationPermission, LocationSettings;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:portfolio/utils/heatmap/brutal.dart';
import 'package:portfolio/utils/heatmap/heat_data.dart';
import 'package:portfolio/utils/heatmap/heat_models.dart';
import 'package:portfolio/utils/heatmap/ph_geo.dart';
import 'package:portfolio/utils/app_theme.dart';

/// Optional CARTO key: flutter run --dart-define=CARTO_API_KEY=xxxx
/// Without it the map uses OpenStreetMap's own tiles (no key needed).
const _cartoKey = String.fromEnvironment('CARTO_API_KEY');

/// 0 = country view, 1 = region, 2 = street level.
int _zoomBand(double zoom) => zoom >= 11 ? 2 : (zoom >= 8 ? 1 : 0);

/// Zoomable street-level map of the Philippines with heat overlays.
/// Tap a province to fill [selectionProvider].
class HeatMapView extends ConsumerStatefulWidget {
  const HeatMapView({super.key, required this.geo, required this.readings});

  final PhGeo geo;

  /// Province name -> live reading.
  final Map<String, WeatherReading> readings;

  @override
  ConsumerState<HeatMapView> createState() => _HeatMapViewState();
}

class _HeatMapViewState extends ConsumerState<HeatMapView> {
  final _map = MapController();
  static const _phCenter = LatLng(12.5, 122.0);
  static const _phZoom = 5.2;

  Timer? _viewportTimer;

  LatLng? _me; // the user's last found location
  bool _locating = false;

  // Province polygons are expensive to build, so they are cached and only
  // rebuilt when their inputs change (not on every pan/zoom frame).
  List<Polygon> _provPolys = const [];
  PhGeo? _cGeo;
  Map<String, WeatherReading>? _cReadings;
  HeatMode? _cMode;
  int? _cBand;
  Color? _cInk;

  @override
  void dispose() {
    _viewportTimer?.cancel();
    _map.dispose();
    super.dispose();
  }

  /// Publishes the viewport only once the map has stopped moving, so the
  /// widget tree isn't rebuilt on every frame of a pan or zoom.
  void _publishViewport() {
    _viewportTimer?.cancel();
    _viewportTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final cam = _map.camera;
      ref.read(viewportProvider.notifier).set(
            MapViewport(cam.visibleBounds, cam.zoom),
          );
    });
  }

  void _zoomBy(double d) {
    final cam = _map.camera;
    _map.move(cam.center, (cam.zoom + d).clamp(4.0, 19.0));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Finds the user's position, zooms to it and selects it so the detail
  /// panel shows the local heat index and nearby cool-down spots.
  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Location services are turned off.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Location permission was denied. Allow it in your browser or '
            'device settings to use this button.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;

      final ll = LatLng(pos.latitude, pos.longitude);
      setState(() => _me = ll);
      _map.move(ll, 15);

      final province = widget.geo.hit(
        widget.geo.project(ll.longitude, ll.latitude),
      );
      ref.read(selectionProvider.notifier).select(
            Selection(
              lat: ll.latitude,
              lon: ll.longitude,
              province: province?.name ?? 'Your location',
            ),
          );
    } catch (_) {
      _toast('Could not get your location. Please try again.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _onTap(LatLng ll) {
    final g = widget.geo.project(ll.longitude, ll.latitude);
    final province = widget.geo.hit(g);
    if (province == null) return; // sea
    ref.read(selectionProvider.notifier).select(
          Selection(
            lat: ll.latitude,
            lon: ll.longitude,
            province: province.name,
          ),
        );
  }

  List<Polygon> _provincePolygons({
    required HeatMode mode,
    required int band,
    required Color ink,
    required Color noData,
  }) {
    final same = identical(_cGeo, widget.geo) &&
        identical(_cReadings, widget.readings) &&
        _cMode == mode &&
        _cBand == band &&
        _cInk == ink;
    if (same) return _provPolys;

    final alpha = const [150, 60, 30][band];
    final bands = bandsFor(mode);
    _provPolys = [
      for (final prov in widget.geo.provinces)
        for (final ring in prov.latLngPolygons)
          Polygon(
            points: ring,
            color: (widget.readings[prov.name] == null
                    ? noData
                    : bands[bandIndex(
                            bands, widget.readings[prov.name]!.valueFor(mode))]
                        .color)
                .withAlpha(alpha),
            borderColor: ink.withAlpha(120),
            borderStrokeWidth: 1.0,
          ),
    ];
    _cGeo = widget.geo;
    _cReadings = widget.readings;
    _cMode = mode;
    _cBand = band;
    _cInk = ink;
    return _provPolys;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final mode = ref.watch(heatModeProvider);
    final selection = ref.watch(selectionProvider);
    final grid = ref.watch(gridWeatherProvider).valueOrNull ?? const [];
    // Only rebuild when the zoom crosses a band, not on every zoom change.
    final band = ref.watch(
      viewportProvider.select((v) => _zoomBand(v?.zoom ?? _phZoom)),
    );
    final bands = bandsFor(mode);

    final provPolys = _provincePolygons(
      mode: mode,
      band: band,
      ink: p.ink,
      noData: p.chip,
    );

    // Outline of the selected province (small, cheap to rebuild).
    final selectedPolys = <Polygon>[
      if (selection != null)
        for (final prov
            in widget.geo.provinces.where((x) => x.name == selection.province))
          for (final ring in prov.latLngPolygons)
            Polygon(
              points: ring,
              color: Colors.transparent,
              borderColor: p.ink,
              borderStrokeWidth: 0.5,
            ),
    ];

    // Only show lattice bubbles that fall on land.
    final landGrid = [
      for (final g in grid)
        if (widget.geo.hit(widget.geo.project(g.point.lon, g.point.lat)) !=
            null)
          g,
    ];

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _phCenter,
            initialZoom: _phZoom,
            minZoom: 4,
            maxZoom: 19,
            // containCenter only limits the center point, so it still holds
            // when the visible area is wider than these bounds (low zoom).
            cameraConstraint: CameraConstraint.containCenter(
              bounds: LatLngBounds(const LatLng(3, 114), const LatLng(23, 130)),
            ),
            // No rotation: fewer gesture conflicts and less work per frame.
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: _publishViewport,
            onPositionChanged: (_, __) => _publishViewport(),
            onTap: (_, ll) => _onTap(ll),
          ),
          children: [
            TileLayer(
              urlTemplate: _cartoKey.isEmpty
                  ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                  : 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png?key=$_cartoKey',
              userAgentPackageName: 'com.yourname.portfolio', // change me
              maxNativeZoom: 19,
              keepBuffer: 2,
            ),
            RepaintBoundary(
              child: PolygonLayer(
                polygons: provPolys,
                simplificationTolerance: 1.0, // higher = faster, less detail
              ),
            ),
            if (selectedPolys.isNotEmpty) PolygonLayer(polygons: selectedPolys),
            // Detailed sampled temperatures + selection pin
            MarkerLayer(
              markers: [
                for (final g in landGrid)
                  Marker(
                    point: LatLng(g.point.lat, g.point.lon),
                    width: 44,
                    height: 44,
                    child: _TempBubble(
                      value: g.reading.valueFor(mode),
                      color: bands[bandIndex(bands, g.reading.valueFor(mode))]
                          .color,
                      ink: p.ink,
                    ),
                  ),
                if (_me != null)
                  Marker(
                    point: _me!,
                    width: 16,
                    height: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F80ED),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
                if (selection != null)
                  Marker(
                    point: LatLng(selection.lat, selection.lon),
                    width: 16,
                    height: 16,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.lime,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.ink, width: 0.5),
                      ),
                    ),
                  ),
              ],
            ),
            RichAttributionWidget(
              alignment: AttributionAlignment.bottomLeft,
              attributions: [
                const TextSourceAttribution('© OpenStreetMap contributors'),
                if (_cartoKey.isNotEmpty) const TextSourceAttribution('© CARTO'),
                const TextSourceAttribution('Weather: Open-Meteo'),
              ],
            ),
          ],
        ),
        Positioned(
          top: 8,
          right: 8,
          child: Column(
            children: [
              BrutalButton(
                icon: Icons.add,
                tooltip: 'Zoom in',
                onTap: () => _zoomBy(1),
              ),
              const SizedBox(height: 6),
              BrutalButton(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onTap: () => _zoomBy(-1),
              ),
              const SizedBox(height: 6),
              BrutalButton(
                icon: Icons.center_focus_strong,
                tooltip: 'Reset view',
                onTap: () => _map.move(_phCenter, _phZoom),
              ),
              const SizedBox(height: 6),
              BrutalButton(
                icon: _locating ? Icons.hourglass_top : Icons.my_location,
                tooltip: 'My location',
                onTap: _locate,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TempBubble extends StatelessWidget {
  const _TempBubble({
    required this.value,
    required this.color,
    required this.ink,
  });

  final double value;
  final Color color;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final onColor =
        color.computeLuminance() > 0.45 ? AppColors.ink : AppColors.white;
    return Container(
      decoration: BoxDecoration(
        color: color.withAlpha(220),
        shape: BoxShape.circle,
        border: Border.all(color: ink, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '${value.round()}°',
        style: TextStyle(
          color: onColor,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}