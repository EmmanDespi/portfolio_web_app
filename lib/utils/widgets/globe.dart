// planet_globe.dart  (performance-optimized)
//
// A 3D planet viewer for Flutter. Every planet's surface is generated
// procedurally and rendered as a lit, rotatable sphere. Drag to rotate (with
// inertia); it also spins slowly on its own axis when idle.
//
// Requires one package for pausing offscreen globes:
//   flutter pub add visibility_detector
//
// Optimizations vs. the original:
//   1. Lower mesh resolution (32 x 64 instead of 56 x 112)
//   2. Ticker is muted while the globe is offscreen
//   3. Animation capped at ~30 fps
//   4. MaskFilter blurs replaced with radial gradients / removed
//   5. Stars painted once on their own RepaintBoundary layer
//   6. Globe layer isolated with a RepaintBoundary
//
// Usage:
//   SizedBox(height: 520, child: PlanetGlobe())
//   Expanded(child: PlanetGlobe(initialPlanet: Planet.saturn))

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:visibility_detector/visibility_detector.dart';

enum Planet {
  sun,
  mercury,
  venus,
  earth,
  moon,
  mars,
  jupiter,
  saturn,
  uranus,
  neptune,
  asteroid,
  comet,
  redGiant,
  blueStar,
  pulsar,
  blackHole,
}

// ─────────────────────────────────────────────────────────────────────────────
// Public widget
// ─────────────────────────────────────────────────────────────────────────────

class PlanetGlobe extends StatefulWidget {
  const PlanetGlobe({
    super.key,
    this.initialPlanet = Planet.earth,
    this.showSelector = true,
    this.showInfo = true,
    this.showStars = true,
    this.autoSpin = true,
    this.backgroundColor = const Color(0xFF050814),
    this.textColor = Colors.white,
    this.accentColor = const Color(0xFFFFC857),
    this.borderRadius = BorderRadius.zero,
  });

  final Planet initialPlanet;
  final bool showSelector; // planet dropdown along the bottom
  final bool showInfo; // name + facts overlay (top-left)
  final bool showStars;
  final bool autoSpin; // slow spin when the user isn't dragging
  final Color backgroundColor; // use Colors.transparent to blend with parent
  final Color textColor;
  final Color accentColor;
  final BorderRadius borderRadius;

  @override
  State<PlanetGlobe> createState() => _PlanetGlobeState();
}

class _PlanetGlobeState extends State<PlanetGlobe>
    with SingleTickerProviderStateMixin {
  // Cap the animation at ~30 fps. A slowly spinning planet doesn't need more.
  static const Duration _frameInterval = Duration(milliseconds: 33);

  late final _GlobeController _ctrl;
  late final Ticker _ticker;
  late Planet _planet;
  final Key _visKey = UniqueKey();
  Duration _lastProcessed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _planet = widget.initialPlanet;
    _ctrl = _GlobeController(_planet);
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final since = elapsed - _lastProcessed;
    if (since < _frameInterval) return;
    var dt = since.inMicroseconds / 1e6;
    _lastProcessed = elapsed;
    if (dt > 0.05) dt = 0.05; // avoids a jump after being muted/offscreen
    _ctrl.advance(dt, widget.autoSpin);
  }

  void _onVisibility(VisibilityInfo info) {
    if (!mounted) return;
    // A muted ticker doesn't fire callbacks, so offscreen globes cost nothing.
    _ticker.muted = info.visibleFraction == 0;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _select(Planet p) {
    if (p == _planet) return;
    setState(() => _planet = p);
    _ctrl.setPlanet(p);
  }

  @override
  Widget build(BuildContext context) {
    final spec = _specs[_planet]!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final h = constraints.hasBoundedHeight ? constraints.maxHeight : 480.0;
        return VisibilityDetector(
          key: _visKey,
          onVisibilityChanged: _onVisibility,
          child: SizedBox(
            height: h,
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: ColoredBox(
                color: widget.backgroundColor,
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          // Static starfield: painted once, never repainted.
                          if (widget.showStars)
                            const Positioned.fill(
                              child: IgnorePointer(
                                child: RepaintBoundary(
                                  child: CustomPaint(painter: _StarsPainter()),
                                ),
                              ),
                            ),
                          // Animated globe on its own layer.
                          Positioned.fill(
                            child: MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (_) => _ctrl.startDrag(),
                                onPanUpdate: (d) =>
                                    _ctrl.drag(d.delta.dx, d.delta.dy),
                                onPanEnd: (d) =>
                                    _ctrl.endDrag(d.velocity.pixelsPerSecond),
                                onPanCancel: () => _ctrl.endDrag(Offset.zero),
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    painter: _GlobePainter(_ctrl),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (widget.showInfo)
                            Positioned(
                              left: 14,
                              top: 12,
                              child: IgnorePointer(child: _buildInfo(spec)),
                            ),
                        ],
                      ),
                    ),
                    if (widget.showSelector) _buildSelector(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfo(_PlanetSpec spec) {
    final label = TextStyle(
      color: widget.textColor.withAlpha(150),
      fontSize: 12,
      height: 1.5,
    );
    final value = TextStyle(
      color: widget.textColor,
      fontSize: 12,
      height: 1.5,
      fontWeight: FontWeight.w600,
    );
    Widget row(String l, String v) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$l  ', style: label),
            Text(v, style: value),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          spec.name.toUpperCase(),
          style: TextStyle(
            color: widget.textColor,
            fontSize: 20,
            letterSpacing: 3,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        for (final f in spec.facts) row(f.key, f.value),
      ],
    );
  }

  Widget _buildSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: widget.accentColor, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<Planet>(
            value: _planet,
            isExpanded: true,
            dropdownColor: const Color(0xFF111A33), // menu background
            iconEnabledColor: widget.textColor,
            borderRadius: BorderRadius.circular(8),
            menuMaxHeight: 360,
            style: TextStyle(
              color: widget.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            items: Planet.values.map((p) {
              final s = _specs[p]!;
              return DropdownMenuItem<Planet>(
                value: p,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | s.dot),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(s.name),
                  ],
                ),
              );
            }).toList(),
            onChanged: (p) {
              if (p != null) _select(p);
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Controller: rotation state, mesh buffers
// ─────────────────────────────────────────────────────────────────────────────

class _GlobeController extends ChangeNotifier {
  _GlobeController(Planet p) {
    setPlanet(p, notify: false);
  }

  late _PlanetSpec spec;
  late _Mesh mesh;

  // Orientation set by the user (view space), spin about the planet's own axis.
  List<double> userRot = _rotX(0.35); // tilt north pole slightly toward viewer
  double spin = 0;
  double vx = 0, vy = 0; // inertia, rad/s
  bool dragging = false;

  // Reusable per-frame buffers
  final Float32List positions = Float32List(_Mesh.vertexCount * 2);
  final Int32List colors = Int32List(_Mesh.vertexCount);
  final Float32List zs = Float32List(_Mesh.vertexCount);
  final Uint16List visible = Uint16List(_Mesh.quadCount * 6);

  void setPlanet(Planet p, {bool notify = true}) {
    spec = _specs[p]!;
    mesh = _meshCache.putIfAbsent(p, () => _Mesh.build(spec));
    if (notify) notifyListeners();
  }

  void startDrag() {
    dragging = true;
    vx = vy = 0;
  }

  void drag(double dx, double dy) {
    const k = 0.008;
    userRot = _ortho(_mul(_rotX(dy * k), _mul(_rotY(dx * k), userRot)));
    notifyListeners();
  }

  void endDrag(Offset velocityPxPerSec) {
    dragging = false;
    const k = 0.008;
    vx = (velocityPxPerSec.dx * k).clamp(-6.0, 6.0).toDouble();
    vy = (velocityPxPerSec.dy * k).clamp(-6.0, 6.0).toDouble();
  }

  void advance(double dt, bool autoSpin) {
    var changed = false;
    if (!dragging) {
      if (vx.abs() + vy.abs() > 0.02) {
        userRot = _ortho(_mul(_rotX(vy * dt), _mul(_rotY(vx * dt), userRot)));
        final decay = math.exp(-2.2 * dt);
        vx *= decay;
        vy *= decay;
        changed = true;
      }
      if (autoSpin) {
        spin += spec.spinRate * dt;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }
}

final Map<Planet, _Mesh> _meshCache = {};

// ─────────────────────────────────────────────────────────────────────────────
// Stars: static layer, painted once
// ─────────────────────────────────────────────────────────────────────────────

final List<List<double>> _starField = () {
  final rnd = math.Random(7);
  return List.generate(
    90,
    (_) => [
      rnd.nextDouble(),
      rnd.nextDouble(),
      rnd.nextDouble() * 1.1 + 0.3,
      rnd.nextDouble() * 0.6 + 0.3,
    ],
  );
}();

class _StarsPainter extends CustomPainter {
  const _StarsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final s in _starField) {
      p.color = Colors.white.withAlpha((s[3] * 255).round());
      canvas.drawCircle(Offset(s[0] * size.width, s[1] * size.height), s[2], p);
    }
  }

  @override
  bool shouldRepaint(covariant _StarsPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter
// ─────────────────────────────────────────────────────────────────────────────

class _GlobePainter extends CustomPainter {
  _GlobePainter(this.c) : super(repaint: c);

  final _GlobeController c;

  // Light direction in view space (upper-left, towards the viewer)
  static final double _lightLen =
      math.sqrt(0.55 * 0.55 + 0.45 * 0.45 + 0.70 * 0.70);
  static final double _lx = -0.55 / _lightLen;
  static final double _ly = 0.45 / _lightLen;
  static final double _lz = 0.70 / _lightLen;

  /// Cheap soft glow: a radial gradient that fades to transparent.
  /// [solidUntil] is the radius (in px) where the full colour ends.
  static void _glow(
    Canvas canvas,
    Offset center,
    double solidUntil,
    double outer,
    Color color,
  ) {
    canvas.drawCircle(
      center,
      outer,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          outer,
          [color, color.withAlpha(0)],
          [(solidUntil / outer).clamp(0.0, 0.99).toDouble(), 1.0],
        ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final spec = c.spec;
    final half = math.min(size.width, size.height) / 2;
    final center = Offset(
      size.width / 2 + spec.offset.dx * size.width,
      size.height / 2 + spec.offset.dy * size.height,
    );
    final radius = half *
        (spec.viewScale ??
            (spec.rings.isNotEmpty ? 0.40 : (spec.emissive ? 0.70 : 0.84)));

    // Matrices: ring frame (no spin) and surface frame (with spin).
    final base = _mul(c.userRot, _rotZ(spec.tiltDeg * math.pi / 180));
    final model = _mul(base, _rotY(c.spin));

    if (spec.kind == _Kind.blackHole) {
      _drawBlackHole(canvas, center, radius, base, spec);
      return;
    }

    if (spec.decor == _Decor.comet) _drawComet(canvas, center, radius);

    // Glow (radial gradient instead of an expensive blur)
    if (spec.atmosphereStrength > 0) {
      final glowAlpha =
          spec.emissive ? 190 : (spec.atmosphereStrength * 110).round();
      final outer = radius * (spec.emissive ? 1.55 : 1.18);
      _glow(
        canvas,
        center,
        radius * 0.92,
        outer,
        Color(0xFF000000 | spec.atmosphere).withAlpha(glowAlpha),
      );
    }

    // Back of the rings / back pulsar beam, then the body, then the front.
    if (spec.rings.isNotEmpty) {
      _drawRings(canvas, center, radius, base, spec.rings, front: false);
    }
    if (spec.decor == _Decor.pulsar) {
      _drawPulsarBeams(canvas, center, radius, model, front: false);
    }

    _drawSphere(canvas, center, radius, model, spec);

    if (spec.rings.isNotEmpty) {
      _drawRings(canvas, center, radius, base, spec.rings, front: true);
    }
    if (spec.decor == _Decor.pulsar) {
      _drawPulsarBeams(canvas, center, radius, model, front: true);
    }
  }

  // ── Body mesh ────────────────────────────────────────────────────────────

  void _drawSphere(
    Canvas canvas,
    Offset center,
    double r,
    List<double> m,
    _PlanetSpec spec,
  ) {
    final mesh = c.mesh;
    final pos = mesh.pos;
    final nrm = mesh.nrm;
    final alb = mesh.albedo;
    final sameNormals = identical(pos, nrm);
    final out = c.positions;
    final col = c.colors;
    final zs = c.zs;

    final atmR = ((spec.atmosphere >> 16) & 255) / 255.0;
    final atmG = ((spec.atmosphere >> 8) & 255) / 255.0;
    final atmB = (spec.atmosphere & 255) / 255.0;
    final atmK = spec.emissive ? 0.0 : spec.atmosphereStrength;

    for (var v = 0; v < _Mesh.vertexCount; v++) {
      final x = pos[v * 3];
      final y = pos[v * 3 + 1];
      final z = pos[v * 3 + 2];

      final rx = m[0] * x + m[1] * y + m[2] * z;
      final ry = m[3] * x + m[4] * y + m[5] * z;
      final rz = m[6] * x + m[7] * y + m[8] * z;

      out[v * 2] = center.dx + rx * r;
      out[v * 2 + 1] = center.dy - ry * r;

      // Surface normal (differs from the position on irregular bodies)
      var nx = rx, ny = ry, nz = rz;
      if (!sameNormals) {
        final a = nrm[v * 3], b = nrm[v * 3 + 1], d = nrm[v * 3 + 2];
        nx = m[0] * a + m[1] * b + m[2] * d;
        ny = m[3] * a + m[4] * b + m[5] * d;
        nz = m[6] * a + m[7] * b + m[8] * d;
      }
      zs[v] = nz;

      double diffuse, light;
      if (spec.emissive) {
        // Self-lit (stars): no shadow side, just mild limb darkening.
        diffuse = 1;
        light = 0.62 + 0.38 * (nz < 0 ? 0 : nz);
      } else {
        diffuse = nx * _lx + ny * _ly + nz * _lz;
        if (diffuse < 0) diffuse = 0;
        light = 0.10 + 0.90 * diffuse;
      }

      final rim = 1 - (nz < 0 ? 0 : nz);
      final atm = rim * rim * rim * atmK * (0.25 + 0.75 * diffuse);

      var rr = alb[v * 3] * light + atmR * atm;
      var gg = alb[v * 3 + 1] * light + atmG * atm;
      var bb = alb[v * 3 + 2] * light + atmB * atm;
      if (rr > 1) rr = 1;
      if (gg > 1) gg = 1;
      if (bb > 1) bb = 1;

      col[v] = (0xFF << 24) |
          ((rr * 255).toInt() << 16) |
          ((gg * 255).toInt() << 8) |
          (bb * 255).toInt();
    }

    final idx = _Mesh.indices;
    final vis = c.visible;
    var n = 0;

    // Pass 1: quads turned slightly away. Drawn first, they only show where a
    // hairline crack would otherwise appear along the silhouette.
    for (var q = 0; q < _Mesh.quadCount; q++) {
      final o = q * 6;
      final sum = zs[idx[o]] + zs[idx[o + 1]] + zs[idx[o + 2]] + zs[idx[o + 5]];
      if (sum <= 0 && sum > -0.8) {
        for (var k = 0; k < 6; k++) {
          vis[n++] = idx[o + k];
        }
      }
    }
    // Pass 2: quads facing the viewer.
    for (var q = 0; q < _Mesh.quadCount; q++) {
      final o = q * 6;
      final sum = zs[idx[o]] + zs[idx[o + 1]] + zs[idx[o + 2]] + zs[idx[o + 5]];
      if (sum > 0) {
        for (var k = 0; k < 6; k++) {
          vis[n++] = idx[o + k];
        }
      }
    }
    if (n == 0) return;

    final verts = ui.Vertices.raw(
      ui.VertexMode.triangles,
      out,
      colors: col,
      indices: Uint16List.sublistView(vis, 0, n),
    );

    canvas.save();
    if (spec.shape == null) {
      // Perfect spheres: clip to the disc for a clean antialiased edge.
      canvas.clipPath(
          Path()..addOval(Rect.fromCircle(center: center, radius: r)));
      canvas.drawCircle(center, r, Paint()..color = const Color(0xFF0A0A10));
    }
    canvas.drawVertices(verts, BlendMode.src, Paint());
    canvas.restore();
    verts.dispose();
  }

  // ── Rings (Saturn, and the black hole's accretion disk) ─────────────────

  /// Rings lie in the body's equatorial plane. Points with z > 0 are in front
  /// of the body, z < 0 behind it, so the back arc is drawn first and the
  /// front arc after the body.
  void _drawRings(
    Canvas canvas,
    Offset center,
    double r,
    List<double> base,
    List<_RingBand> bands, {
    required bool front,
  }) {
    final ux = base[0], uy = base[3], uz = base[6];
    final wx = base[2], wy = base[5], wz = base[8];

    final theta0 = math.atan2(wz, uz); // angle where the ring is closest
    final start = front ? theta0 - math.pi / 2 : theta0 + math.pi / 2;
    const steps = 40;
    const sweep = math.pi;

    final cosT = List<double>.filled(steps + 1, 0);
    final sinT = List<double>.filled(steps + 1, 0);
    for (var k = 0; k <= steps; k++) {
      final t = start + sweep * k / steps;
      cosT[k] = math.cos(t);
      sinT[k] = math.sin(t);
    }

    final paint = Paint()..style = PaintingStyle.fill;
    for (final b in bands) {
      final path = Path();
      for (var k = 0; k <= steps; k++) {
        final px = center.dx + r * b.outer * (cosT[k] * ux + sinT[k] * wx);
        final py = center.dy - r * b.outer * (cosT[k] * uy + sinT[k] * wy);
        if (k == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      for (var k = steps; k >= 0; k--) {
        final px = center.dx + r * b.inner * (cosT[k] * ux + sinT[k] * wx);
        final py = center.dy - r * b.inner * (cosT[k] * uy + sinT[k] * wy);
        path.lineTo(px, py);
      }
      path.close();
      paint.color = b.color;
      canvas.drawPath(path, paint);
    }
  }

  // ── Black hole ───────────────────────────────────────────────────────────

  /// A stylised black hole: accretion disk (brighter on the approaching side),
  /// light from the far side of the disk bent over the top and under the
  /// bottom, a thin photon ring, and the black shadow itself.
  void _drawBlackHole(
    Canvas canvas,
    Offset center,
    double r,
    List<double> base,
    _PlanetSpec spec,
  ) {
    final bounds = Rect.fromCircle(center: center, radius: r * 4.8);

    // Soft glow around the whole system (gradient, no blur)
    _glow(
      canvas,
      center,
      r * 1.2,
      r * 3.8,
      const Color(0xFFFF8A2A).withAlpha(70),
    );

    // Far side of the disk
    _diskLayer(canvas, center, r, base, spec.rings,
        front: false, bounds: bounds);

    // Lensed image of the far side: a bright arch on the side the disk's
    // normal points to, fading to a thin ring on the opposite side. Face-on,
    // it becomes an even ring.
    final sgn = base[7] >= 0 ? 1.0 : -1.0;
    final a = math.atan2(-base[4] * sgn, base[1] * sgn);
    final contrast = math.sqrt(math.max(0.0, 1 - base[7] * base[7]));
    final lensRect = Rect.fromCircle(center: center, radius: r * 2.6);
    for (var i = 0; i < 6; i++) {
      final f = 1 - i / 7;
      final rgb = _mix(0xFFF0C0, 0xFF8A2A, i / 5);
      final peak = Color(((f * 255).round() << 24) | rgb);
      final dim =
          Color(((f * (1 - 0.7 * contrast) * 255).round() << 24) | rgb);
      canvas.drawCircle(
        center,
        r * (1.06 + 0.2 * i),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.16
          ..shader = SweepGradient(
            colors: [peak, dim, peak],
            stops: const [0.0, 0.5, 1.0],
            transform: GradientRotation(a),
          ).createShader(lensRect),
      );
    }

    // Shadow + photon ring
    canvas.drawCircle(center, r, Paint()..color = const Color(0xFF000000));
    canvas.drawCircle(
      center,
      r * 1.02,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.05
        ..color = const Color(0xFFFFF2CC),
    );

    // Near side of the disk (passes in front of the shadow)
    _diskLayer(canvas, center, r, base, spec.rings,
        front: true, bounds: bounds);
  }

  /// Draws half of the disk into an offscreen layer and fades it left to
  /// right: relativistic beaming makes the approaching side brighter.
  void _diskLayer(
    Canvas canvas,
    Offset center,
    double r,
    List<double> base,
    List<_RingBand> bands, {
    required bool front,
    required Rect bounds,
  }) {
    canvas.saveLayer(bounds, Paint());
    _drawRings(canvas, center, r, base, bands, front: front);
    canvas.drawRect(
      bounds,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = ui.Gradient.linear(
          bounds.centerLeft,
          bounds.centerRight,
          const [Color(0xFFFFFFFF), Color(0x55FFFFFF)],
        ),
    );
    canvas.restore();
  }

  // ── Comet ────────────────────────────────────────────────────────────────

  /// Tails always point away from the light, so they trail down and to the
  /// right while the nucleus tumbles.
  void _drawComet(Canvas canvas, Offset center, double r) {
    final dir = Offset(0.55, 0.45) / math.sqrt(0.55 * 0.55 + 0.45 * 0.45);
    final dust = _rot(dir, 0.32);

    _wedge(canvas, center, dust, r * 9, r * 1.0, r * 3.6,
        const Color(0x99E8C890)); // curved, yellowish dust tail
    _wedge(canvas, center, dir, r * 14, r * 0.7, r * 1.8,
        const Color(0xAA7FC8FF)); // straight, blue ion tail

    canvas.drawCircle(
      // the coma: a halo of gas around the nucleus
      center,
      r * 2.2,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          r * 2.2,
          const [Color(0x99DDEEFF), Color(0x00DDEEFF)],
        ),
    );
  }

  // ── Pulsar ───────────────────────────────────────────────────────────────

  /// Two beams along the magnetic axis, which is tilted away from the spin
  /// axis, so they sweep around like a lighthouse. A beam pointing at the
  /// viewer shows up as a flash.
  void _drawPulsarBeams(
    Canvas canvas,
    Offset center,
    double r,
    List<double> m, {
    required bool front,
  }) {
    const beta = 0.87; // ~50 degrees between magnetic and spin axes
    final ax = math.sin(beta), ay = math.cos(beta);
    final bx = m[0] * ax + m[1] * ay;
    final by = m[3] * ax + m[4] * ay;
    final bz = m[6] * ax + m[7] * ay;
    final flat = math.sqrt(bx * bx + by * by);

    for (final s in const [1.0, -1.0]) {
      final vz = s * bz;
      if ((vz > 0) != front) continue;
      if (flat > 0.02) {
        final dir = Offset(s * bx, -s * by) / flat;
        _wedge(canvas, center, dir, r * 6 * flat, r * 0.35, r * 1.0,
            const Color(0xE6BFE0FF));
      }
      if (vz > 0.25) {
        // Flash as a gradient instead of a blur
        _glow(
          canvas,
          center,
          r * 0.4,
          r * (2.2 + 3.5 * vz),
          const Color(0xFFBFE0FF).withAlpha((vz * 190).round()),
        );
      }
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// A tapered wedge that fades out along its length (tails, beams).
  void _wedge(
    Canvas canvas,
    Offset from,
    Offset dir,
    double len,
    double w0,
    double w1,
    Color color,
  ) {
    final perp = Offset(-dir.dy, dir.dx);
    final tip = from + dir * len;
    final path = Path()
      ..moveTo(from.dx + perp.dx * w0, from.dy + perp.dy * w0)
      ..lineTo(tip.dx + perp.dx * w1, tip.dy + perp.dy * w1)
      ..lineTo(tip.dx - perp.dx * w1, tip.dy - perp.dy * w1)
      ..lineTo(from.dx - perp.dx * w0, from.dy - perp.dy * w0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = ui.Gradient.linear(from, tip, [color, color.withAlpha(0)]),
    );
  }

  Offset _rot(Offset v, double a) => Offset(
        v.dx * math.cos(a) - v.dy * math.sin(a),
        v.dx * math.sin(a) + v.dy * math.cos(a),
      );

  @override
  bool shouldRepaint(covariant _GlobePainter old) => old.c != c;
}

// ─────────────────────────────────────────────────────────────────────────────
// Mesh: a lat/long sphere whose per-vertex colours come from the planet's
// procedural surface function.
// ─────────────────────────────────────────────────────────────────────────────

class _Mesh {
  _Mesh._(this.albedo, this.pos, this.nrm);

  // Lower this further (e.g. 28 x 56) if you still need more speed, or raise
  // it (e.g. 56 x 112) for a single large hero globe. Keep
  // (rows + 1) * (cols + 1) under 65536 (Uint16 indices).
  static const int rows = 32; // latitude bands
  static const int cols = 64; // longitude segments
  static const int vertexCount = (rows + 1) * (cols + 1);
  static const int quadCount = rows * cols;

  static final Float32List unit = _buildUnit();
  static final Uint16List indices = _buildIndices();

  final Float32List albedo; // rgb 0..1 per vertex
  final Float32List pos; // vertex positions (== unit for perfect spheres)
  final Float32List nrm; // vertex normals (identical(pos, nrm) if spherical)

  factory _Mesh.build(_PlanetSpec spec) {
    final shape = spec.shape;
    final a = Float32List(vertexCount * 3);
    final p = shape == null ? unit : Float32List(vertexCount * 3);

    for (var v = 0; v < vertexCount; v++) {
      final ux = unit[v * 3], uy = unit[v * 3 + 1], uz = unit[v * 3 + 2];
      final hex = spec.albedo(ux, uy, uz);
      a[v * 3] = ((hex >> 16) & 255) / 255.0;
      a[v * 3 + 1] = ((hex >> 8) & 255) / 255.0;
      a[v * 3 + 2] = (hex & 255) / 255.0;
      if (shape != null) {
        final k = shape(ux, uy, uz);
        p[v * 3] = ux * k * spec.stretch[0];
        p[v * 3 + 1] = uy * k * spec.stretch[1];
        p[v * 3 + 2] = uz * k * spec.stretch[2];
      }
    }
    return _Mesh._(a, p, shape == null ? unit : _normals(p));
  }

  /// Normals from neighbouring vertices, so lumps and craters catch the light.
  static Float32List _normals(Float32List p) {
    final out = Float32List(vertexCount * 3);
    const w = cols + 1;
    for (var i = 0; i <= rows; i++) {
      final i0 = i > 0 ? i - 1 : 0;
      final i1 = i < rows ? i + 1 : rows;
      for (var j = 0; j <= cols; j++) {
        final j0 = j > 0 ? j - 1 : cols - 1;
        final j1 = j < cols ? j + 1 : 1;
        final v = i * w + j;

        final ea = (i * w + j1) * 3, eb = (i * w + j0) * 3; // along longitude
        final nc = (i1 * w + j) * 3, nd = (i0 * w + j) * 3; // along latitude
        final tx = p[ea] - p[eb],
            ty = p[ea + 1] - p[eb + 1],
            tz = p[ea + 2] - p[eb + 2];
        final sx = p[nc] - p[nd],
            sy = p[nc + 1] - p[nd + 1],
            sz = p[nc + 2] - p[nd + 2];

        var nx = ty * sz - tz * sy;
        var ny = tz * sx - tx * sz;
        var nz = tx * sy - ty * sx;

        final ux = unit[v * 3], uy = unit[v * 3 + 1], uz = unit[v * 3 + 2];
        if (nx * ux + ny * uy + nz * uz < 0) {
          nx = -nx;
          ny = -ny;
          nz = -nz;
        }
        var len = math.sqrt(nx * nx + ny * ny + nz * nz);
        if (len < 1e-9) {
          // degenerate at the poles: fall back to the sphere normal
          nx = ux;
          ny = uy;
          nz = uz;
          len = 1;
        }
        out[v * 3] = nx / len;
        out[v * 3 + 1] = ny / len;
        out[v * 3 + 2] = nz / len;
      }
    }
    return out;
  }

  static Float32List _buildUnit() {
    final out = Float32List(vertexCount * 3);
    var k = 0;
    for (var i = 0; i <= rows; i++) {
      final lat = math.pi / 2 - math.pi * i / rows;
      final cl = math.cos(lat), sl = math.sin(lat);
      for (var j = 0; j <= cols; j++) {
        final lon = 2 * math.pi * j / cols - math.pi;
        out[k++] = cl * math.sin(lon);
        out[k++] = sl;
        out[k++] = cl * math.cos(lon);
      }
    }
    return out;
  }

  // Per quad: [a, c, b,  b, c, d]
  static Uint16List _buildIndices() {
    final out = Uint16List(quadCount * 6);
    var k = 0;
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        final a = i * (cols + 1) + j;
        final b = a + 1;
        final c = a + (cols + 1);
        final d = c + 1;
        out[k++] = a;
        out[k++] = c;
        out[k++] = b;
        out[k++] = b;
        out[k++] = c;
        out[k++] = d;
      }
    }
    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Planet data
// ─────────────────────────────────────────────────────────────────────────────

class _RingBand {
  const _RingBand(this.inner, this.outer, this.color);
  final double inner; // in planet radii
  final double outer;
  final Color color;
}

enum _Kind { body, blackHole }

enum _Decor { none, comet, pulsar }

class _PlanetSpec {
  _PlanetSpec({
    required this.name,
    required this.tiltDeg,
    required this.dot,
    required this.atmosphere,
    required this.atmosphereStrength,
    required this.diameter,
    required this.rotation,
    required this.moons,
    required this.albedo,
    this.rings = const [],
    this.emissive = false,
    this.diameterLabel = 'Diameter',
    this.rotationLabel = 'Rotation',
    this.moonsLabel = 'Moons',
    this.shape,
    this.stretch = const [1.0, 1.0, 1.0],
    this.kind = _Kind.body,
    this.decor = _Decor.none,
    this.viewScale,
    this.offset = Offset.zero,
    this.spinRate = 0.3,
  });

  final String name;
  final double tiltDeg; // axial tilt
  final int dot; // 0xRRGGBB for the selector
  final int atmosphere; // 0xRRGGBB rim/glow colour
  final double atmosphereStrength; // 0..1
  final String diameter;
  final String rotation;
  final String moons; // leave empty to hide the third info row
  final int Function(double x, double y, double z) albedo; // unit-sphere point
  final List<_RingBand> rings;
  final bool emissive; // self-lit, ignores the light direction

  // Labels for the three info rows
  final String diameterLabel;
  final String rotationLabel;
  final String moonsLabel;

  // Irregular bodies: radial multiplier per direction + axis stretch
  final double Function(double x, double y, double z)? shape;
  final List<double> stretch;

  final _Kind kind;
  final _Decor decor;
  final double? viewScale; // body radius as a fraction of half the view
  final Offset offset; // shift from centre, as a fraction of the view size
  final double spinRate; // rad/s about the body's own axis

  List<MapEntry<String, String>> get facts => [
        MapEntry(diameterLabel, diameter),
        MapEntry(rotationLabel, rotation),
        if (moons.isNotEmpty) MapEntry(moonsLabel, moons),
      ];
}

final Map<Planet, _PlanetSpec> _specs = {
  Planet.sun: _PlanetSpec(
    name: 'Sun',
    tiltDeg: 7.25,
    dot: 0xFFB300,
    atmosphere: 0xFFB347,
    atmosphereStrength: 1.0,
    diameter: '1,392,700 km',
    rotation: '~25 Earth days (equator)',
    moons: '8',
    moonsLabel: 'Planets',
    albedo: _sun,
    emissive: true,
  ),
  Planet.moon: _PlanetSpec(
    name: 'Moon',
    tiltDeg: 6.7,
    dot: 0xC9C7C0,
    atmosphere: 0x000000,
    atmosphereStrength: 0,
    diameter: '3,474 km',
    rotation: '27.3 Earth days (tidally locked)',
    moons: '0',
    albedo: _moon,
  ),
  Planet.mercury: _PlanetSpec(
    name: 'Mercury',
    tiltDeg: 0.03,
    dot: 0xB5AEA5,
    atmosphere: 0x000000,
    atmosphereStrength: 0,
    diameter: '4,879 km',
    rotation: '58.6 Earth days',
    moons: '0',
    albedo: _mercury,
  ),
  Planet.venus: _PlanetSpec(
    name: 'Venus',
    tiltDeg: 177.4,
    dot: 0xE8C77A,
    atmosphere: 0xFFD98A,
    atmosphereStrength: 0.55,
    diameter: '12,104 km',
    rotation: '243 Earth days (retrograde)',
    moons: '0',
    albedo: _venus,
  ),
  Planet.earth: _PlanetSpec(
    name: 'Earth',
    tiltDeg: 23.4,
    dot: 0x3F86D6,
    atmosphere: 0x6FB6FF,
    atmosphereStrength: 0.9,
    diameter: '12,742 km',
    rotation: '23.9 hours',
    moons: '1',
    albedo: _earth,
  ),
  Planet.mars: _PlanetSpec(
    name: 'Mars',
    tiltDeg: 25.2,
    dot: 0xC1663A,
    atmosphere: 0xE2A07A,
    atmosphereStrength: 0.25,
    diameter: '6,779 km',
    rotation: '24.6 hours',
    moons: '2',
    albedo: _mars,
  ),
  Planet.jupiter: _PlanetSpec(
    name: 'Jupiter',
    tiltDeg: 3.1,
    dot: 0xD2A877,
    atmosphere: 0xF0D8B0,
    atmosphereStrength: 0.25,
    diameter: '139,820 km',
    rotation: '9.9 hours',
    moons: '90+',
    albedo: _jupiter,
  ),
  Planet.saturn: _PlanetSpec(
    name: 'Saturn',
    tiltDeg: 26.7,
    dot: 0xE3CF9E,
    atmosphere: 0xF0DDB0,
    atmosphereStrength: 0.25,
    diameter: '116,460 km',
    rotation: '10.7 hours',
    moons: '270+',
    albedo: _saturn,
    rings: _saturnRings(),
  ),
  Planet.uranus: _PlanetSpec(
    name: 'Uranus',
    tiltDeg: 97.8,
    dot: 0x9FDDE3,
    atmosphere: 0xA8F0F5,
    atmosphereStrength: 0.7,
    diameter: '50,724 km',
    rotation: '17.2 hours (retrograde)',
    moons: '28+',
    albedo: _uranus,
  ),
  Planet.neptune: _PlanetSpec(
    name: 'Neptune',
    tiltDeg: 28.3,
    dot: 0x3F63DB,
    atmosphere: 0x5C8CFF,
    atmosphereStrength: 0.8,
    diameter: '49,244 km',
    rotation: '16.1 hours',
    moons: '16',
    albedo: _neptune,
  ),
  Planet.asteroid: _PlanetSpec(
    name: 'Asteroid',
    tiltDeg: 12,
    dot: 0x8F857A,
    atmosphere: 0x000000,
    atmosphereStrength: 0,
    diameter: 'Meters to ~500 km',
    rotation: 'Hours to days',
    moons: 'Mostly between Mars and Jupiter',
    diameterLabel: 'Size',
    rotationLabel: 'Spin',
    moonsLabel: 'Found',
    albedo: _asteroid,
    shape: _asteroidShape,
    stretch: const [1.2, 0.85, 1.0],
    viewScale: 0.56,
    spinRate: 0.5,
  ),
  Planet.comet: _PlanetSpec(
    name: 'Comet',
    tiltDeg: 20,
    dot: 0x9FD4FF,
    atmosphere: 0xBFE4FF,
    atmosphereStrength: 0,
    diameter: '~1-30 km',
    rotation: 'Hours to days',
    moons: 'Millions of km',
    diameterLabel: 'Nucleus',
    rotationLabel: 'Spin',
    moonsLabel: 'Tail length',
    albedo: _cometNucleus,
    shape: _cometShape,
    stretch: const [1.2, 0.8, 0.9],
    viewScale: 0.20,
    offset: const Offset(-0.22, -0.18),
    spinRate: 0.4,
    decor: _Decor.comet,
  ),
  Planet.redGiant: _PlanetSpec(
    name: 'Red giant',
    tiltDeg: 5,
    dot: 0xE5502A,
    atmosphere: 0xFF3A1A,
    atmosphereStrength: 1.0,
    diameter: 'Up to ~1.2 billion km',
    rotation: '~3,500 K',
    moons: 'Late in life',
    rotationLabel: 'Surface temp',
    moonsLabel: 'Stage',
    albedo: _redGiant,
    emissive: true,
    viewScale: 0.66,
    spinRate: 0.08,
  ),
  Planet.blueStar: _PlanetSpec(
    name: 'Blue star',
    tiltDeg: 8,
    dot: 0x7FB2FF,
    atmosphere: 0x6AA8FF,
    atmosphereStrength: 1.0,
    diameter: '~10-100 million km',
    rotation: '10,000-40,000 K',
    moons: 'Millions of years',
    rotationLabel: 'Surface temp',
    moonsLabel: 'Lifespan',
    albedo: _blueStar,
    emissive: true,
    viewScale: 0.58,
    spinRate: 0.5,
  ),
  Planet.pulsar: _PlanetSpec(
    name: 'Pulsar',
    tiltDeg: 20,
    dot: 0xBFE0FF,
    atmosphere: 0x9CC8FF,
    atmosphereStrength: 1.0,
    diameter: '~20 km',
    rotation: '1 ms to ~10 s per turn',
    moons: 'Billions of tonnes per teaspoon',
    rotationLabel: 'Spin',
    moonsLabel: 'Density',
    albedo: _pulsar,
    emissive: true,
    viewScale: 0.15,
    spinRate: 2.4,
    decor: _Decor.pulsar,
  ),
  Planet.blackHole: _PlanetSpec(
    name: 'Black hole',
    tiltDeg: 0,
    dot: 0xFF9A2A,
    atmosphere: 0xFF8A2A,
    atmosphereStrength: 0,
    diameter: '~59 km (10 solar masses)',
    rotation: 'Nothing escapes, not even light',
    moons: 'Gas heated to millions of degrees',
    diameterLabel: 'Event horizon',
    rotationLabel: 'Gravity',
    moonsLabel: 'Accretion disk',
    albedo: _blank,
    kind: _Kind.blackHole,
    rings: _blackHoleDisk(),
    viewScale: 0.20,
  ),
};

List<_RingBand> _blackHoleDisk() {
  final out = <_RingBand>[];
  const step = 0.07;
  for (double rho = 1.3; rho < 4.3; rho += step) {
    final t = (rho - 1.3) / 3.0;
    // white-hot inner edge fading through orange to deep red
    final rgb = t < 0.5
        ? _mix(0xFFFBE8, 0xFFB347, t * 2)
        : _mix(0xFFB347, 0x8C2A0E, (t - 0.5) * 2);
    final a = _clamp01(
      (0.95 * math.pow(1 - t, 1.3) + 0.05 + 0.08 * math.sin(rho * 55))
          .toDouble(),
    );
    out.add(_RingBand(
        rho, rho + step + 0.004, Color(((a * 255).round() << 24) | rgb)));
  }
  return out;
}

List<_RingBand> _saturnRings() {
  final out = <_RingBand>[];
  const step = 0.03;
  for (double r = 1.24; r < 2.27; r += step) {
    double a;
    if (r < 1.52) {
      a = 0.16 + 0.06 * math.sin(r * 60); // C ring: faint
    } else if (r < 1.95) {
      a = 0.82 + 0.12 * math.sin(r * 85); // B ring: dense
    } else if (r < 2.03) {
      a = 0.05; // Cassini division
    } else {
      a = 0.62 + 0.12 * math.sin(r * 110); // A ring
    }
    final t = (math.sin(r * 37) + 1) / 2;
    final rgb = _mix(0xA8927A, 0xE8D6A8, t);
    final alpha = (_clamp01(a) * 255).round();
    out.add(_RingBand(r, r + step + 0.004, Color((alpha << 24) | rgb)));
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// Procedural surfaces. Each takes a unit-sphere point and returns 0xRRGGBB.
// ─────────────────────────────────────────────────────────────────────────────

int _mercury(double x, double y, double z) {
  final g = _fbm(x * 4, y * 4, z * 4, octaves: 6);
  var c = _mix(0x6E6862, 0xB8B0A6, (g - 0.25) / 0.5);
  final crater = _fbm(x * 14 + 3, y * 14, z * 14, octaves: 3);
  if (crater > 0.62) c = _mix(c, 0x4A4642, (crater - 0.62) * 5);
  if (crater < 0.30) c = _mix(c, 0xD9D2C7, (0.30 - crater) * 3);
  return c;
}

int _sun(double x, double y, double z) {
  final lat = math.asin(_clampSym(y));
  final warp = _fbm(x * 2, y * 2, z * 2, octaves: 3);
  // Granulation: boiling convection cells
  final g = _fbm(x * 9 + warp * 2, y * 9 + warp * 2, z * 9, octaves: 5);
  final t = (g - 0.35) / 0.3;
  var c = t < 0.5
      ? _mix(0xE5600A, 0xFF9A1F, t * 2)
      : _mix(0xFF9A1F, 0xFFE27A, (t - 0.5) * 2);
  // Sunspots, confined to the active latitudes
  final s = _fbm(x * 2.5 + 11, y * 2.5, z * 2.5, octaves: 3);
  if (s > 0.60 && lat.abs() < 0.6) c = _mix(c, 0x3A1405, (s - 0.60) * 8);
  return c;
}

int _moon(double x, double y, double z) {
  final g = _fbm(x * 5, y * 5, z * 5, octaves: 6);
  var c = _mix(0x8A8A88, 0xC4C2BC, (g - 0.25) / 0.5);
  // Maria: dark volcanic plains
  final m = _fbm(x * 1.6 + 3, y * 1.6, z * 1.6, octaves: 4);
  if (m > 0.52) c = _mix(c, 0x4E4E50, (m - 0.52) * 5);
  // Craters
  final crater = _fbm(x * 16 + 5, y * 16, z * 16, octaves: 3);
  if (crater > 0.62) c = _mix(c, 0x3E3E40, (crater - 0.62) * 5);
  if (crater < 0.30) c = _mix(c, 0xE6E4DE, (0.30 - crater) * 3);
  return c;
}

int _blank(double x, double y, double z) => 0x000000;

// Crater centres (x, y, z, angular radius in radians) for the asteroid.
final List<List<double>> _asteroidCraters = [
  [0.5, 0.6, 0.6, 0.42],
  [-0.7, 0.2, 0.7, 0.30],
  [0.2, -0.8, 0.5, 0.35],
  [-0.4, -0.3, -0.85, 0.40],
  [0.9, -0.1, -0.3, 0.28],
  [-0.2, 0.9, -0.3, 0.24],
  [0.6, -0.4, 0.7, 0.22],
].map((c) {
  final l = math.sqrt(c[0] * c[0] + c[1] * c[1] + c[2] * c[2]);
  return [c[0] / l, c[1] / l, c[2] / l, c[3]];
}).toList();

/// Radial multiplier: lumpy potato with bowl-shaped craters and raised rims.
double _asteroidShape(double x, double y, double z) {
  final lump = _fbm(x * 1.3 + 2, y * 1.3, z * 1.3 + 7, octaves: 4);
  final fine = _fbm(x * 5, y * 5, z * 5, octaves: 3);
  var r = 0.72 + 0.62 * lump + 0.10 * fine;
  for (final c in _asteroidCraters) {
    final d = math.acos(_clampSym(x * c[0] + y * c[1] + z * c[2]));
    final cr = c[3];
    if (d < cr) {
      final k = d / cr;
      r -= 0.10 * (1 - k * k);
    } else if (d < cr * 1.25) {
      final k = (d - cr) / (cr * 0.25);
      r += 0.025 * (1 - k);
    }
  }
  return r;
}

int _asteroid(double x, double y, double z) {
  final g = _fbm(x * 7, y * 7, z * 7, octaves: 5);
  var c = _mix(0x5A524A, 0x9A8F82, (g - 0.3) / 0.4);
  final d = _fbm(x * 2.5 + 13, y * 2.5, z * 2.5, octaves: 3);
  if (d > 0.55) c = _mix(c, 0x2E2B28, (d - 0.55) * 5); // dark carbon-rich patches
  final f = _fbm(x * 18, y * 18, z * 18, octaves: 2);
  c = _mix(c, 0xB5AB9C, (f - 0.62) * 3); // bright dust and boulders
  return c;
}

double _cometShape(double x, double y, double z) {
  final lump = _fbm(x * 1.2 + 31, y * 1.2, z * 1.2 + 4, octaves: 4);
  final fine = _fbm(x * 5 + 8, y * 5, z * 5, octaves: 3);
  return 0.78 + 0.55 * lump + 0.08 * fine;
}

int _cometNucleus(double x, double y, double z) {
  final g = _fbm(x * 6, y * 6, z * 6, octaves: 5);
  var c = _mix(0x2A2624, 0x6E6560, (g - 0.3) / 0.4); // dark dusty crust
  final ice = _fbm(x * 3.5 + 9, y * 3.5, z * 3.5, octaves: 3);
  if (ice > 0.58) c = _mix(c, 0xDDE8F0, (ice - 0.58) * 5); // exposed ice
  return c;
}

int _redGiant(double x, double y, double z) {
  final warp = _fbm(x * 1.5, y * 1.5, z * 1.5, octaves: 3);
  // Huge convection cells, far bigger than the Sun's granules
  final g = _fbm(x * 3 + warp * 2, y * 3 + warp * 2, z * 3, octaves: 4);
  final t = (g - 0.3) / 0.4;
  var c = t < 0.5
      ? _mix(0x8A1A08, 0xE2481A, t * 2)
      : _mix(0xE2481A, 0xFFA060, (t - 0.5) * 2);
  final h = _fbm(x * 10 + 5, y * 10, z * 10, octaves: 3);
  if (h > 0.62) c = _mix(c, 0xFFD090, (h - 0.62) * 4);
  return c;
}

int _blueStar(double x, double y, double z) {
  final warp = _fbm(x * 2.5, y * 2.5, z * 2.5, octaves: 3);
  final g = _fbm(x * 6 + warp * 2, y * 6 + warp * 2, z * 6, octaves: 5);
  final t = (g - 0.35) / 0.3;
  return t < 0.5
      ? _mix(0x3F72E8, 0x7FB2FF, t * 2)
      : _mix(0x7FB2FF, 0xE8F4FF, (t - 0.5) * 2);
}

int _pulsar(double x, double y, double z) {
  final g = _fbm(x * 5, y * 5, z * 5, octaves: 3);
  return _mix(0x9CC8FF, 0xFFFFFF, (g - 0.3) / 0.4);
}

int _venus(double x, double y, double z) {
  final w = _fbm(x * 2, y * 2, z * 2, octaves: 3);
  final n = _fbm(x * 3 + w * 2.5, y * 6 + w * 1.5, z * 3 + w * 2.5, octaves: 4);
  return _mix(0xC79A55, 0xF3E1A8, (n - 0.3) / 0.4);
}

int _earth(double x, double y, double z) {
  final lat = math.asin(_clampSym(y));
  final h = _fbm(x * 2.0 + 5, y * 2.0, z * 2.0 + 9, octaves: 6);
  const sea = 0.53;
  int c;
  if (h < sea) {
    c = _mix(0x2B6FB8, 0x0B2E6B, (sea - h) * 5); // shallow -> deep
  } else {
    final e = _clamp01((h - sea) * 4);
    final dry = _fbm(x * 3, y * 3, z * 3 + 20, octaves: 3);
    var land = _mix(0x3F8F3F, 0x2E6B33, dry * 1.5 - 0.3);
    final a = lat.abs();
    if (a > 0.25 && a < 0.62) {
      land = _mix(land, 0xC9B27A, (dry - 0.45) * 3); // deserts
    }
    c = _mix(land, 0x8A7A55, e); // mountains
  }
  final capEdge = 1.15 + 0.2 * _fbm(x * 5, y * 5, z * 5, octaves: 3);
  if (lat.abs() > capEdge) c = _mix(c, 0xF4F8FC, (lat.abs() - capEdge) * 12);
  final cl = _fbm(x * 3.5 + 40, y * 6, z * 3.5, octaves: 5);
  if (cl > 0.55) {
    c = _mix(c, 0xFFFFFF,
        (cl - 0.55) * 3.5 > 0.85 ? 0.85 : (cl - 0.55) * 3.5);
  }
  return c;
}

int _mars(double x, double y, double z) {
  final lat = math.asin(_clampSym(y));
  final g = _fbm(x * 3, y * 3, z * 3, octaves: 5);
  var c = _mix(0xD0764A, 0xA9552F, (g - 0.3) / 0.4);
  final d = _fbm(x * 2 + 7, y * 2, z * 2, octaves: 4);
  if (d > 0.54) c = _mix(c, 0x5C3324, (d - 0.54) * 5);
  if (lat.abs() > 1.36) c = _mix(c, 0xF2F2F2, (lat.abs() - 1.36) * 12);
  return c;
}

int _jupiter(double x, double y, double z) {
  final lat = math.asin(_clampSym(y));
  final lon = math.atan2(x, z);
  final t = _fbm(x * 5, y * 1.4, z * 5, octaves: 5);
  final v = (math.sin(lat * 10 + t * 2.8) + 1) / 2;
  var c = v < 0.5
      ? _mix(0x9A6040, 0xCB9A6A, v * 2)
      : _mix(0xCB9A6A, 0xF0E2C8, (v - 0.5) * 2);
  final s = _fbm(x * 14, y * 2.5, z * 14, octaves: 3);
  c = _mix(c, 0x7A4A30, (s - 0.5) * 0.8);

  // Great Red Spot
  final dLon = _wrapPi(lon - 0.7) * math.cos(lat);
  final dLat = lat + 0.38;
  final e = (dLon / 0.36) * (dLon / 0.36) + (dLat / 0.17) * (dLat / 0.17);
  if (e < 1) c = _mix(c, 0xB8472E, _smooth(1 - e) * 0.95);
  return c;
}

int _saturn(double x, double y, double z) {
  final lat = math.asin(_clampSym(y));
  final t = _fbm(x * 4, y * 1.0, z * 4, octaves: 4);
  final v = (math.sin(lat * 8 + t * 1.5) + 1) / 2;
  var c = _mix(0xC9AE7A, 0xEBDCAB, v);
  if (lat.abs() > 1.1) c = _mix(c, 0x8E8F8C, (lat.abs() - 1.1) * 1.8);
  return c;
}

int _uranus(double x, double y, double z) {
  final lat = math.asin(_clampSym(y));
  final t = _fbm(x * 3, y * 1.2, z * 3, octaves: 3);
  final v = (math.sin(lat * 6 + t * 1.2) + 1) / 2;
  var c = _mix(0x9FDDE3, 0x86CBD6, v * 0.6);
  c = _mix(c, 0xC4F2F4, (lat.abs() - 0.9) * 1.2);
  return c;
}

int _neptune(double x, double y, double z) {
  final lat = math.asin(_clampSym(y));
  final lon = math.atan2(x, z);
  final t = _fbm(x * 4, y * 1.3, z * 4, octaves: 4);
  final v = (math.sin(lat * 7 + t * 1.8) + 1) / 2;
  var c = _mix(0x2A47C9, 0x4E7BEB, v);

  // Great Dark Spot
  final dLon = _wrapPi(lon + 0.4) * math.cos(lat);
  final dLat = lat + 0.35;
  final e = (dLon / 0.30) * (dLon / 0.30) + (dLat / 0.15) * (dLat / 0.15);
  if (e < 1) c = _mix(c, 0x16277A, _smooth(1 - e) * 0.9);

  // High cirrus streaks
  final s = _fbm(x * 7, y * 14, z * 7 + 3, octaves: 4);
  if (s > 0.62) {
    c = _mix(c, 0xE8F0FF, (s - 0.62) * 2.5 > 0.7 ? 0.7 : (s - 0.62) * 2.5);
  }
  return c;
}

// ─────────────────────────────────────────────────────────────────────────────
// Math helpers: colour mixing, noise, 3x3 matrices
// ─────────────────────────────────────────────────────────────────────────────

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
double _clampSym(double v) => v < -1 ? -1 : (v > 1 ? 1 : v);
double _smooth(double t) => t * t * (3 - 2 * t);

double _wrapPi(double a) {
  while (a > math.pi) {
    a -= 2 * math.pi;
  }
  while (a < -math.pi) {
    a += 2 * math.pi;
  }
  return a;
}

/// Blend two 0xRRGGBB colours.
int _mix(int a, int b, double t) {
  t = _clamp01(t);
  final ar = (a >> 16) & 255, ag = (a >> 8) & 255, ab = a & 255;
  final br = (b >> 16) & 255, bg = (b >> 8) & 255, bb = b & 255;
  final r = (ar + (br - ar) * t).round();
  final g = (ag + (bg - ag) * t).round();
  final bl = (ab + (bb - ab) * t).round();
  return (r << 16) | (g << 8) | bl;
}

double _hash(int x, int y, int z) {
  final s = math.sin(x * 12.9898 + y * 78.233 + z * 37.719) * 43758.5453;
  return s - s.floorToDouble();
}

double _noise(double x, double y, double z) {
  final xi = x.floor(), yi = y.floor(), zi = z.floor();
  final u = _smooth(x - xi), v = _smooth(y - yi), w = _smooth(z - zi);
  double l(double a, double b, double t) => a + (b - a) * t;
  return l(
    l(
      l(_hash(xi, yi, zi), _hash(xi + 1, yi, zi), u),
      l(_hash(xi, yi + 1, zi), _hash(xi + 1, yi + 1, zi), u),
      v,
    ),
    l(
      l(_hash(xi, yi, zi + 1), _hash(xi + 1, yi, zi + 1), u),
      l(_hash(xi, yi + 1, zi + 1), _hash(xi + 1, yi + 1, zi + 1), u),
      v,
    ),
    w,
  );
}

/// Fractal noise, roughly 0..1 centred on 0.5.
double _fbm(double x, double y, double z, {int octaves = 5}) {
  var sum = 0.0, amp = 0.5, f = 1.0, norm = 0.0;
  for (var i = 0; i < octaves; i++) {
    sum += amp * _noise(x * f + i * 17.31, y * f + i * 9.17, z * f + i * 5.73);
    norm += amp;
    amp *= 0.5;
    f *= 2.03;
  }
  return sum / norm;
}

// Row-major 3x3 matrices
List<double> _mul(List<double> a, List<double> b) => [
      a[0] * b[0] + a[1] * b[3] + a[2] * b[6],
      a[0] * b[1] + a[1] * b[4] + a[2] * b[7],
      a[0] * b[2] + a[1] * b[5] + a[2] * b[8],
      a[3] * b[0] + a[4] * b[3] + a[5] * b[6],
      a[3] * b[1] + a[4] * b[4] + a[5] * b[7],
      a[3] * b[2] + a[4] * b[5] + a[5] * b[8],
      a[6] * b[0] + a[7] * b[3] + a[8] * b[6],
      a[6] * b[1] + a[7] * b[4] + a[8] * b[7],
      a[6] * b[2] + a[7] * b[5] + a[8] * b[8],
    ];

List<double> _rotX(double a) {
  final c = math.cos(a), s = math.sin(a);
  return [1, 0, 0, 0, c, -s, 0, s, c];
}

List<double> _rotY(double a) {
  final c = math.cos(a), s = math.sin(a);
  return [c, 0, s, 0, 1, 0, -s, 0, c];
}

List<double> _rotZ(double a) {
  final c = math.cos(a), s = math.sin(a);
  return [c, -s, 0, s, c, 0, 0, 0, 1];
}

/// Re-orthonormalise so repeated multiplications don't drift.
List<double> _ortho(List<double> m) {
  var nx = m[0], ny = m[1], nz = m[2];
  var l = math.sqrt(nx * nx + ny * ny + nz * nz);
  nx /= l;
  ny /= l;
  nz /= l;
  var bx = m[3], by = m[4], bz = m[5];
  final d = bx * nx + by * ny + bz * nz;
  bx -= d * nx;
  by -= d * ny;
  bz -= d * nz;
  l = math.sqrt(bx * bx + by * by + bz * bz);
  bx /= l;
  by /= l;
  bz /= l;
  final cx = ny * bz - nz * by;
  final cy = nz * bx - nx * bz;
  final cz = nx * by - ny * bx;
  return [nx, ny, nz, bx, by, bz, cx, cy, cz];
}