import 'dart:ui';

import 'package:material_ui/material_ui.dart';

/// Shared motion for the floating bar and the transitions that travel with it.
abstract final class LiquidGlassMotion {
  static const duration = Duration(milliseconds: 500);
  static const curve = Curves.easeInOutCubicEmphasized;
}

/// Translucent fill, backdrop blur, a thin luminous edge, and a soft specular
/// highlight. High contrast keeps an opaque fill so icons and labels stay
/// readable. There is no in-app reduce-transparency switch; glass stays on
/// otherwise.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    this.color,
    this.elevation = 0,
    this.shadowColor,
    this.blurSigma = 22,
    this.framed = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Color? color;
  final double elevation;
  final Color? shadowColor;

  /// `0` skips the backdrop filter. Nested lenses sit on an already blurred
  /// surface, so they only add the fill, edge, and highlight.
  final double blurSigma;

  /// Luminous edge and shadow. Transition washes turn this off.
  final bool framed;

  static bool reduceTransparencyOf(BuildContext context) {
    return MediaQuery.highContrastOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ColorScheme.of(context);
    final isDark = colors.brightness == Brightness.dark;
    final solid = blurSigma > 0 && reduceTransparencyOf(context);
    final useBlur = blurSigma > 0 && !solid;
    final lens = !solid;

    final fill = _fill(colors, solid: solid);
    final edge = solid ? colors.outlineVariant : _edge(colors);

    final shape = RoundedSuperellipseBorder(borderRadius: borderRadius);
    Widget glass = DecoratedBox(
      decoration: ShapeDecoration(
        gradient: lens ? _sheen(fill, isDark: isDark) : null,
        color: lens ? null : fill,
        shape: shape,
      ),
      child: child,
    );

    glass = ClipPath(
      clipper: _ShapeClipper(shape),
      child: useBlur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: glass,
            )
          : glass,
    );

    if (!framed) return glass;

    final List<BoxShadow>? shadows;
    if (elevation <= 0 || shadowColor == Colors.transparent) {
      shadows = null;
    } else {
      shadows = [
        BoxShadow(
          color:
              shadowColor ??
              (isDark ? const Color(0x47000000) : const Color(0x14000000)),
          blurRadius: 4 + elevation * 4,
          offset: Offset(0, elevation * 2),
        ),
      ];
    }

    return DecoratedBox(
      decoration: ShapeDecoration(shape: shape, shadows: shadows),
      child: Stack(
        children: [
          glass,
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: borderRadius,
                    side: BorderSide(color: edge, width: 1),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _fill(ColorScheme colors, {required bool solid}) {
    if (solid) {
      return color ?? colors.surfaceContainer;
    }
    final provided = color;
    if (provided != null && provided.a < 0.999) {
      return provided;
    }
    final base = provided ?? colors.surface;
    return base.withValues(alpha: colors.brightness == .dark ? 0.90 : 0.82);
  }

  Color _edge(ColorScheme colors) {
    if (colors.brightness == .dark) {
      return const Color(0x80FFFFFF);
    }
    return Color.alphaBlend(
      colors.outline.withValues(alpha: 0.16),
      const Color(0xF7FFFFFF),
    );
  }

  LinearGradient _sheen(Color fill, {required bool isDark}) {
    final highlight = Color.lerp(
      fill,
      Colors.white.withValues(alpha: isDark ? 0.34 : 0.92),
      isDark ? 0.42 : 0.58,
    )!;
    final shade = Color.lerp(
      fill,
      Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
      0.28,
    )!;
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [highlight, fill, shade],
      stops: const [0.0, 0.38, 1.0],
    );
  }
}

/// Glass wash for a shell transition driven by a tab index animation.
/// Opacity is 0 on a settled tab and peaks halfway between tabs.
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
          fit: .expand,
          children: [
            child!,
            if (show)
              Positioned.fill(
                child: IgnorePointer(
                  child: Opacity(
                    opacity: travel * 0.32,
                    child: const LiquidGlass(
                      borderRadius: BorderRadius.zero,
                      elevation: 0,
                      blurSigma: 16,
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
