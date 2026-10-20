import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:portfolio/utils/app_theme.dart';

/// What the map colors by.
enum HeatMode { heatIndex, temperature }

/// One color step of the legend / map.
class HeatBand {
  const HeatBand(this.label, this.min, this.color, [this.effect = '']);

  final String label;

  /// Inclusive lower bound (°C).
  final double min;
  final Color color;

  /// Short health note (heat-index bands only).
  final String effect;

  Color get onColor =>
      color.computeLuminance() > 0.45 ? AppColors.ink : AppColors.white;
}

const _orange = Color(0xFFFF9F45);
const _yellow = Color(0xFFFFE066);
const _darkRed = Color(0xFF8C1C13);
const _skyBlue = Color(0xFF9CCBE8);

/// PAGASA heat-index categories (°C).
const heatIndexBands = <HeatBand>[
  HeatBand(
    'Not hazardous',
    double.negativeInfinity,
    AppColors.lime,
    'Comfortable for most people. Keep water handy.',
  ),
  HeatBand(
    'Caution',
    27,
    _yellow,
    'Fatigue is possible with prolonged exposure and activity.',
  ),
  HeatBand(
    'Extreme caution',
    33,
    _orange,
    'Heat cramps and heat exhaustion are possible. Continued activity could lead to heat stroke.',
  ),
  HeatBand(
    'Danger',
    42,
    AppColors.coral,
    'Heat cramps and heat exhaustion are likely. Heat stroke is probable with continued activity.',
  ),
  HeatBand(
    'Extreme danger',
    52,
    _darkRed,
    'Heat stroke is imminent.',
  ),
];

const temperatureBands = <HeatBand>[
  HeatBand('Cool', double.negativeInfinity, _skyBlue),
  HeatBand('Mild', 25, AppColors.lime),
  HeatBand('Warm', 28, _yellow),
  HeatBand('Hot', 31, _orange),
  HeatBand('Very hot', 34, AppColors.coral),
  HeatBand('Scorching', 37, _darkRed),
];

List<HeatBand> bandsFor(HeatMode mode) =>
    mode == HeatMode.heatIndex ? heatIndexBands : temperatureBands;

int bandIndex(List<HeatBand> bands, double value) {
  var index = 0;
  for (var i = 0; i < bands.length; i++) {
    if (value >= bands[i].min) index = i;
  }
  return index;
}

/// NWS / Rothfusz heat index, in °C. [rh] is relative humidity in percent.
double computeHeatIndexC(double tempC, double rh) {
  final t = tempC * 9 / 5 + 32;
  var hi = 0.5 * (t + 61.0 + ((t - 68.0) * 1.2) + (rh * 0.094));

  if ((hi + t) / 2 >= 80) {
    hi = -42.379 +
        2.04901523 * t +
        10.14333127 * rh -
        0.22475541 * t * rh -
        0.00683783 * t * t -
        0.05481717 * rh * rh +
        0.00122874 * t * t * rh +
        0.00085282 * t * rh * rh -
        0.00000199 * t * t * rh * rh;

    if (rh < 13 && t >= 80 && t <= 112) {
      hi -= ((13 - rh) / 4) * math.sqrt((17 - (t - 95).abs()) / 17);
    } else if (rh > 85 && t >= 80 && t <= 87) {
      hi += ((rh - 85) / 10) * ((87 - t) / 5);
    }
  }
  return (hi - 32) * 5 / 9;
}

class WeatherReading {
  const WeatherReading({
    required this.tempC,
    required this.humidity,
    required this.apparentC,
    this.time,
  });

  final double tempC;
  final double humidity;
  final double apparentC;
  final DateTime? time;

  double get heatIndexC => computeHeatIndexC(tempC, humidity);

  double valueFor(HeatMode mode) =>
      mode == HeatMode.heatIndex ? heatIndexC : tempC;

  /// "15:00" (Philippine local time as returned by the API).
  String? get timeLabel {
    final t = time;
    if (t == null) return null;
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

/// Where the user tapped.
class Selection {
  const Selection({
    required this.lat,
    required this.lon,
    required this.province,
  });

  final double lat;
  final double lon;
  final String province;
}

enum PlaceKind {
  convenience(
    'Convenience store',
    'S',
    AppColors.lime,
    5000,
    ['["shop"="convenience"]'],
  ),
  mall('Mall', 'M', Color(0xFFE5B8F4), 15000, ['["shop"="mall"]']),
  cafe('Café', 'C', _yellow, 5000, ['["amenity"="cafe"]']),
  water(
    'Drinking water',
    'W',
    _skyBlue,
    1500,
    ['["amenity"="drinking_water"]'],
  );

  const PlaceKind(
    this.label,
    this.letter,
    this.color,
    this.maxRadiusM,
    this.osmFilters,
  );

  final String label;
  final String letter;
  final Color color;

  /// Furthest we search for this kind of place.
  final int maxRadiusM;
  final List<String> osmFilters;
}

class Place {
  const Place({
    required this.kind,
    required this.name,
    required this.lat,
    required this.lon,
    required this.distanceM,
  });

  final PlaceKind kind;
  final String name;
  final double lat;
  final double lon;
  final double distanceM;

  String get distanceLabel => distanceM < 1000
      ? '${distanceM.round()} m'
      : '${(distanceM / 1000).toStringAsFixed(1)} km';
}

class NearbyResult {
  const NearbyResult({this.nearest = const {}, this.failed = false});

  final Map<PlaceKind, Place> nearest;

  /// True when at least one lookup failed (timeout, busy server, offline).
  final bool failed;
}

double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLon = rad(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}
