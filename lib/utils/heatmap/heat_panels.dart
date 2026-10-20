import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portfolio/utils/heatmap/brutal.dart';
import 'heat_data.dart';
import 'heat_models.dart';
import 'package:portfolio/utils/app_theme.dart';

TextStyle _label(BuildContext context, {double size = 13}) => TextStyle(
      color: context.palette.ink,
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
    );

TextStyle _body(BuildContext context, {double size = 13}) => TextStyle(
      color: context.palette.ink,
      fontSize: size,
      height: 1.35,
      letterSpacing: 0.6,
    );

/// Heat index / Temperature switch + refresh.
class HeatModeToggle extends ConsumerWidget {
  const HeatModeToggle({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(heatModeProvider);
    final notifier = ref.read(heatModeProvider.notifier);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        BrutalButton(
          label: 'Heat index',
          selected: mode == HeatMode.heatIndex,
          onTap: () => notifier.set(HeatMode.heatIndex),
        ),
        BrutalButton(
          label: 'Temperature',
          selected: mode == HeatMode.temperature,
          onTap: () => notifier.set(HeatMode.temperature),
        ),
        BrutalButton(
          icon: Icons.refresh,
          tooltip: 'Refresh',
          onTap: onRefresh,
        ),
      ],
    );
  }
}

/// Color key for the active mode.
class HeatLegend extends ConsumerWidget {
  const HeatLegend({super.key});

  String _range(List<HeatBand> bands, int i) {
    String f(double v) => v.toStringAsFixed(0);
    if (i == 0) return '< ${f(bands[1].min)}°C';
    if (i == bands.length - 1) return '≥ ${f(bands[i].min)}°C';
    return '${f(bands[i].min)}–${f(bands[i + 1].min)}°C';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final mode = ref.watch(heatModeProvider);
    final bands = bandsFor(mode);

    return BrutalBox(
      color: p.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mode == HeatMode.heatIndex ? 'HEAT INDEX' : 'TEMPERATURE',
            style: _label(context, size: 14),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < bands.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  BrutalBox(
                    color: bands[i].color,
                    shadow: 0,
                    radius: 4,
                    borderWidth: 1.5,
                    padding: EdgeInsets.zero,
                    child: const SizedBox(width: 18, height: 18),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(bands[i].label, style: _body(context))),
                  Text(_range(bands, i), style: _body(context)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Details for the tapped point: exact weather + nearest places.
class HeatDetailPanel extends ConsumerWidget {
  const HeatDetailPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final sel = ref.watch(selectionProvider);

    if (sel == null) {
      return BrutalBox(
        color: p.card,
        child: Text(
          'Tap a province on the map to see its heat index and the nearest '
          'convenience store, mall, café or drinking water.',
          style: _body(context),
        ),
      );
    }

    final point = ref.watch(pointWeatherProvider);
    final nearby = ref.watch(nearbyProvider);
    final area = ref.watch(areaNameProvider).valueOrNull;

    return BrutalBox(
      color: p.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(sel.province, style: _label(context, size: 16)),
              ),
              BrutalButton(
                icon: Icons.close,
                tooltip: 'Clear',
                onTap: () => ref.read(selectionProvider.notifier).clear(),
              ),
            ],
          ),
          if (area != null) ...[
            const SizedBox(height: 4),
            Text(area, style: _body(context)),
          ],
          const SizedBox(height: 4),
          Text(
            '${sel.lat.toStringAsFixed(3)}, ${sel.lon.toStringAsFixed(3)}',
            style: _body(context, size: 12),
          ),
          const SizedBox(height: AppSpacing.sm),
          point.when(
            loading: () => const _Loading('Loading weather…'),
            error: (_, __) => Text('Weather unavailable.', style: _body(context)),
            data: (r) => r == null
                ? Text('No reading for this spot.', style: _body(context))
                : _WeatherBlock(reading: r),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Divider(),
          ),
          Text('NEAREST COOL-DOWN SPOTS', style: _label(context, size: 13)),
          const SizedBox(height: AppSpacing.sm),
          nearby.when(
            loading: () => const _Loading('Searching nearby…'),
            error: (_, __) => Text('Search failed.', style: _body(context)),
            data: (result) => result == null
                ? const SizedBox.shrink()
                : _NearbyBlock(result: result),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.palette.ink,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(text, style: _body(context)),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _body(context, size: 11)),
        Text(value, style: _label(context, size: 16)),
      ],
    );
  }
}

class _WeatherBlock extends StatelessWidget {
  const _WeatherBlock({required this.reading});
  final WeatherReading reading;

  @override
  Widget build(BuildContext context) {
    final band = heatIndexBands[bandIndex(heatIndexBands, reading.heatIndexC)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            _Stat('Temperature', '${reading.tempC.toStringAsFixed(1)}°C'),
            _Stat('Feels like', '${reading.apparentC.toStringAsFixed(1)}°C'),
            _Stat('Humidity', '${reading.humidity.round()}%'),
            _Stat('Heat index', '${reading.heatIndexC.toStringAsFixed(1)}°C'),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        BrutalBox(
          color: band.color,
          shadow: 0,
          radius: 6,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            band.label,
            style: TextStyle(
              color: band.onColor,
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
        if (band.effect.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(band.effect, style: _body(context)),
        ],
        if (reading.timeLabel != null) ...[
          const SizedBox(height: 6),
          Text('As of ${reading.timeLabel} PHT', style: _body(context, size: 11)),
        ],
      ],
    );
  }
}

class _NearbyBlock extends StatelessWidget {
  const _NearbyBlock({required this.result});
  final NearbyResult result;

  @override
  Widget build(BuildContext context) {
    final found = [
      for (final k in PlaceKind.values)
        if (result.nearest[k] != null) result.nearest[k]!,
    ];

    if (found.isEmpty) {
      return Text(
        result.failed
            ? 'Could not reach the places server. Tap again to retry.'
            : 'Nothing found nearby.',
        style: _body(context),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final place in found)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BrutalBox(
                  color: place.kind.color,
                  shadow: 0,
                  radius: 6,
                  borderWidth: 1.5,
                  padding: EdgeInsets.zero,
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                      child: Text(
                        place.kind.letter,
                        style: const TextStyle(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(place.name, style: _label(context, size: 13)),
                      Text(
                        '${place.kind.label} · ${place.distanceLabel}',
                        style: _body(context, size: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (result.failed)
          Text('Some lookups failed; results may be incomplete.',
              style: _body(context, size: 11)),
      ],
    );
  }
}