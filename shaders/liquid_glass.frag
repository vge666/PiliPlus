#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform vec2 u_origin;
uniform vec2 u_extent;
uniform float u_radius;
uniform float u_thickness;
uniform float u_distort;
uniform float u_highlight;
uniform float u_dark;

uniform sampler2D u_texture;

out vec4 frag_color;

float sd_round_box(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + vec2(r);
  return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
#ifdef IMPELLER_TARGET_OPENGLES
  frag.y = u_size.y - frag.y;
#endif

  vec2 local = frag - u_origin;
  vec2 half_ext = max(u_extent * 0.5, vec2(1.0));
  float radius = min(u_radius, min(half_ext.x, half_ext.y) - 0.5);
  radius = max(radius, 0.0);
  vec2 p = local - half_ext;
  float sdf = sd_round_box(p, half_ext, radius);

  vec2 base_uv = frag / u_size;
  if (sdf > 1.0) {
    frag_color = texture(u_texture, base_uv);
    return;
  }

  const float e = 1.35;
  float dx = sd_round_box(p + vec2(e, 0.0), half_ext, radius) -
      sd_round_box(p - vec2(e, 0.0), half_ext, radius);
  float dy = sd_round_box(p + vec2(0.0, e), half_ext, radius) -
      sd_round_box(p - vec2(0.0, e), half_ext, radius);
  vec2 n = vec2(dx, dy);
  float n_len = length(n);
  n = n_len > 0.0001 ? n / n_len : vec2(0.0, -1.0);

  vec2 from_center = p / half_ext;
  float rim = smoothstep(-u_thickness * 22.0, -1.2, sdf);
  float bend = u_distort * (0.25 + rim * 1.75);
  // Convex center pulls light inward; the rim bends it along the normal.
  vec2 offset = n * bend * rim - from_center * (u_distort * 0.18 * u_thickness);
  vec2 chroma = n * rim * (1.15 * u_thickness);

  vec2 sample_px = frag + offset;
  vec3 col;
  col.r = texture(u_texture, clamp((sample_px + chroma) / u_size, vec2(0.001), vec2(0.999))).r;
  col.g = texture(u_texture, clamp(sample_px / u_size, vec2(0.001), vec2(0.999))).g;
  col.b = texture(u_texture, clamp((sample_px - chroma) / u_size, vec2(0.001), vec2(0.999))).b;

  vec3 veil = mix(vec3(0.96, 0.98, 1.0), vec3(0.03, 0.025, 0.04), u_dark);
  col = mix(col, veil, mix(0.10, 0.16, u_dark));

  float rim_d = sdf + 1.25;
  float soft_d = sdf + 3.1;
  float rim_core = exp(-(rim_d * rim_d) * 0.85);
  float rim_soft = exp(-(soft_d * soft_d) * 0.16);
  float top = smoothstep(0.35, -0.9, from_center.y);
  col += vec3(1.0) * (rim_core * (0.42 + 0.7 * top) + rim_soft * 0.28) * (0.65 + 0.35 * u_thickness);

  float lip = smoothstep(-0.15, 0.9, from_center.y) * rim;
  col *= mix(1.0, mix(0.78, 0.62, u_dark), lip * 0.72);

  float hx = local.x / max(u_extent.x, 1.0) - u_highlight;
  float hy = local.y / max(u_extent.y, 1.0) - mix(0.24, 0.18, clamp(u_thickness - 1.0, 0.0, 1.0));
  float streak = exp(-(hy * hy) * (90.0 + u_thickness * 40.0) - (hx * hx) * 6.5);
  float glint = exp(-(hx * hx) * 28.0 - (hy * hy) * 46.0);
  col += vec3(1.0) * (streak * 0.38 + glint * 0.26 * u_thickness);

  frag_color = vec4(col, 1.0);
}
