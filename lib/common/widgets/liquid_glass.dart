import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Shared motion for the floating bar and the transitions that travel with it.
abstract final class LiquidGlassMotion {
  static const duration = Duration(milliseconds: 500);
  static const curve = Curves.easeInOutCubicEmphasized;
}

/// A refractive lens, not a frosted plate.
///
/// The backdrop is bent through a rounded glass profile (stronger at the rim,
/// with a chromatic edge). A bright specular stroke and a traveling highlight
/// sit on that lens. High contrast falls back to an opaque fill.
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    this.thickness = 1.15,
    this.distort = 18,
    this.bead = false,
    this.elevation = 0,
    this.shadowColor,
    this.framed = true,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// Glass thickness. The selection bead uses a higher value than the bar.
  final double thickness;

  /// Refraction distance, in logical pixels, at the rim.
  final double distort;

  /// Thicker edge and a tighter glint, for the selection lens.
  final bool bead;

  final double elevation;
  final Color? shadowColor;

  /// Specular rim, highlight, and shadow. Full-screen washes turn this off.
  final bool framed;

  static bool reduceTransparencyOf(BuildContext context) {
    return MediaQuery.highContrastOf(context);
  }

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _GlassLight extends InheritedWidget {
  const _GlassLight({required this.highlight, required super.child});

  final double highlight;

  static double? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_GlassLight>()?.highlight;
  }

  @override
  bool updateShouldNotify(_GlassLight oldWidget) =>
      highlight != oldWidget.highlight;
}

class _LiquidGlassState extends State<LiquidGlass>
    with SingleTickerProviderStateMixin {
  AnimationController? _clock;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    _LiquidLensProgram.addListener(_onProgram);
    _LiquidLensProgram.ensureLoaded();
  }

  void _onProgram() {
    if (mounted) setState(_attachShader);
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final hasParent =
        context.getInheritedWidgetOfExactType<_GlassLight>() != null;
    if (!hasParent && _clock == null) {
      _clock =
          AnimationController(
              vsync: this,
              duration: const Duration(milliseconds: 3400),
            )
            ..addListener(_tick)
            ..repeat();
    } else if (hasParent && _clock != null) {
      _clock!.dispose();
      _clock = null;
    }
    _attachShader();
  }

  void _attachShader() {
    final program = _LiquidLensProgram.program;
    if (program == null || _shader != null) return;
    if (!ui.ImageFilter.isShaderFilterSupported) return;
    _shader = program.fragmentShader();
  }

  @override
  void dispose() {
    _LiquidLensProgram.removeListener(_onProgram);
    _clock?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  double _highlight(BuildContext context) {
    final inherited = _GlassLight.maybeOf(context);
    if (inherited != null) return inherited;
    final t = _clock?.value ?? 0;
    return 0.12 + 0.76 * (0.5 - 0.5 * math.cos(t * math.pi * 2));
  }

  @override
  Widget build(BuildContext context) {
    _attachShader();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final solid = LiquidGlass.reduceTransparencyOf(context);
    final highlight = _highlight(context);
    final radius = widget.borderRadius
        .resolve(Directionality.of(context))
        .topLeft
        .x;
    final shape = RoundedSuperellipseBorder(borderRadius: widget.borderRadius);

    Widget lens;
    if (solid) {
      final colors = ColorScheme.of(context);
      lens = DecoratedBox(
        decoration: ShapeDecoration(
          color: colors.surfaceContainer,
          shape: RoundedSuperellipseBorder(
            borderRadius: widget.borderRadius,
            side: BorderSide(color: colors.outlineVariant),
          ),
        ),
        child: widget.child,
      );
    } else {
      lens = _LiquidLens(
        shader: _shader,
        thickness: widget.thickness,
        distort: widget.distort,
        radius: radius,
        highlight: widget.bead ? 0.42 + highlight * 0.16 : highlight,
        dark: dark,
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.framed)
              IgnorePointer(
                child: CustomPaint(
                  painter: _GlassEdgePainter(
                    shape: shape,
                    highlight: highlight,
                    bead: widget.bead,
                    dark: dark,
                  ),
                ),
              ),
            IconTheme.merge(
              data: IconThemeData(shadows: _iconHalo(dark)),
              child: DefaultTextStyle.merge(
                style: TextStyle(shadows: _textHalo(dark)),
                child: widget.child,
              ),
            ),
          ],
        ),
      );
    }

    lens = ClipPath(clipper: _ShapeClipper(shape), child: lens);

    if (_clock != null) {
      lens = _GlassLight(highlight: highlight, child: lens);
    }

    if (!widget.framed || widget.elevation <= 0) return lens;
    if (widget.shadowColor == Colors.transparent) return lens;

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: [
          BoxShadow(
            color:
                widget.shadowColor ??
                (dark ? const Color(0x59000000) : const Color(0x24000000)),
            blurRadius: 6 + widget.elevation * 3,
            offset: Offset(0, widget.elevation + 2),
          ),
        ],
      ),
      child: lens,
    );
  }
}

List<Shadow> _iconHalo(bool dark) {
  final color = dark ? const Color(0xE6000000) : const Color(0xF7FFFFFF);
  return [Shadow(color: color, blurRadius: 7)];
}

List<Shadow> _textHalo(bool dark) {
  final color = dark ? const Color(0xD9000000) : const Color(0xF5FFFFFF);
  return [Shadow(color: color, blurRadius: 5)];
}

class _LiquidLens extends SingleChildRenderObjectWidget {
  const _LiquidLens({
    required this.shader,
    required this.thickness,
    required this.distort,
    required this.radius,
    required this.highlight,
    required this.dark,
    required this.devicePixelRatio,
    required super.child,
  });

  final ui.FragmentShader? shader;
  final double thickness;
  final double distort;
  final double radius;
  final double highlight;
  final bool dark;
  final double devicePixelRatio;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderLiquidLens(
      shader: shader,
      thickness: thickness,
      distort: distort,
      radius: radius,
      highlight: highlight,
      dark: dark,
      devicePixelRatio: devicePixelRatio,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderLiquidLens renderObject,
  ) {
    renderObject
      ..shader = shader
      ..thickness = thickness
      ..distort = distort
      ..radius = radius
      ..highlight = highlight
      ..dark = dark
      ..devicePixelRatio = devicePixelRatio;
  }
}

class _RenderLiquidLens extends RenderProxyBox {
  _RenderLiquidLens({
    required ui.FragmentShader? shader,
    required double thickness,
    required double distort,
    required double radius,
    required double highlight,
    required bool dark,
    required double devicePixelRatio,
  }) : _shader = shader,
       _thickness = thickness,
       _distort = distort,
       _radius = radius,
       _highlight = highlight,
       _dark = dark,
       _devicePixelRatio = devicePixelRatio;

  ui.FragmentShader? _shader;
  double _thickness;
  double _distort;
  double _radius;
  double _highlight;
  bool _dark;
  double _devicePixelRatio;

  set shader(ui.FragmentShader? value) {
    if (_shader == value) return;
    _shader = value;
    markNeedsPaint();
  }

  set thickness(double value) {
    if (_thickness == value) return;
    _thickness = value;
    markNeedsPaint();
  }

  set distort(double value) {
    if (_distort == value) return;
    _distort = value;
    markNeedsPaint();
  }

  set radius(double value) {
    if (_radius == value) return;
    _radius = value;
    markNeedsPaint();
  }

  set highlight(double value) {
    if (_highlight == value) return;
    _highlight = value;
    markNeedsPaint();
  }

  set dark(bool value) {
    if (_dark == value) return;
    _dark = value;
    markNeedsPaint();
  }

  set devicePixelRatio(double value) {
    if (_devicePixelRatio == value) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final shader = _shader;
    final ui.ImageFilter filter;
    if (shader != null && ui.ImageFilter.isShaderFilterSupported) {
      final dpr = _devicePixelRatio == 0 ? 1.0 : _devicePixelRatio;
      // The backdrop snapshot is re-rasterized so fragment (0, 0) is this
      // lens's top-left. Extent and radius are in that texture's pixels.
      final extent = size * dpr;
      shader
        ..setFloat(2, 0)
        ..setFloat(3, 0)
        ..setFloat(4, extent.width)
        ..setFloat(5, extent.height)
        ..setFloat(6, _radius * dpr)
        ..setFloat(7, _thickness)
        ..setFloat(8, _distort * dpr)
        ..setFloat(9, _highlight)
        ..setFloat(10, _dark ? 1 : 0);
      filter = ui.ImageFilter.shader(shader);
    } else {
      filter = ui.ImageFilter.blur(
        sigmaX: 1.4,
        sigmaY: 1.4,
        tileMode: TileMode.clamp,
      );
    }

    layer ??= BackdropFilterLayer();
    final backdrop = layer! as BackdropFilterLayer
      ..filter = filter
      ..blendMode = BlendMode.srcOver;
    context.pushLayer(backdrop, super.paint, offset);
  }
}

class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter({
    required this.shape,
    required this.highlight,
    required this.bead,
    required this.dark,
  });

  final ShapeBorder shape;
  final double highlight;
  final bool bead;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect.deflate(bead ? 1.1 : 0.8));
    canvas.save();
    canvas.clipPath(shape.getOuterPath(rect));

    final lip = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bead ? 8 : 5.5
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: bead ? 0.72 : 0.5),
          const Color(0x00FFFFFF),
          Colors.black.withValues(alpha: dark ? 0.62 : 0.30),
        ],
        stops: const [0.0, 0.46, 1.0],
      ).createShader(rect);
    canvas.drawPath(path, lip);

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = bead ? 2.1 : 1.45
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFFFFFFF), Color(0xD9FFFFFF), Color(0x55FFFFFF)],
        stops: [0.0, 0.42, 1.0],
      ).createShader(rect);
    canvas.drawPath(path, rim);

    final cx = size.width * highlight;
    final glow = Rect.fromCenter(
      center: Offset(cx, size.height * (bead ? 0.30 : 0.22)),
      width: size.width * (bead ? 0.86 : 0.34),
      height: size.height * (bead ? 0.62 : 0.5),
    );
    final glint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: bead ? 0.7 : 0.5),
          const Color(0x00FFFFFF),
        ],
      ).createShader(glow);
    canvas.drawOval(glow, glint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassEdgePainter oldDelegate) {
    return oldDelegate.highlight != highlight ||
        oldDelegate.bead != bead ||
        oldDelegate.dark != dark ||
        oldDelegate.shape != shape;
  }
}

class _LiquidLensProgram {
  static ui.FragmentProgram? program;
  static bool _started = false;
  static final Set<VoidCallback> _listeners = <VoidCallback>{};

  static void addListener(VoidCallback listener) => _listeners.add(listener);

  static void removeListener(VoidCallback listener) =>
      _listeners.remove(listener);

  static void ensureLoaded() {
    if (_started) return;
    _started = true;
    ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag').then((value) {
      program = value;
      _notify();
    }, onError: (Object _) => _notify());
  }

  static void _notify() {
    for (final listener in _listeners.toList()) {
      listener();
    }
  }
}

/// Same lens, faded in while the shell tab position is between pages.
class LiquidGlassTransition extends StatelessWidget {
  const LiquidGlassTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value;
        final travel = (value - value.roundToDouble()).abs() * 2;
        final show =
            travel > 0.001 && !LiquidGlass.reduceTransparencyOf(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            child!,
            if (show)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: travel * 0.72,
                    child: const LiquidGlass(
                      borderRadius: BorderRadius.zero,
                      thickness: 0.7,
                      distort: 12,
                      elevation: 0,
                      framed: false,
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      child: child,
    );
  }
}

class _ShapeClipper extends CustomClipper<Path> {
  const _ShapeClipper(this.shape);

  final ShapeBorder shape;

  @override
  Path getClip(Size size) => shape.getOuterPath(Offset.zero & size);

  @override
  bool shouldReclip(_ShapeClipper oldClipper) => oldClipper.shape != shape;
}
