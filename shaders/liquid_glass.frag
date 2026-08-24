#version 320 es

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform sampler2D u_texture;

// Matches Liquify's SVG displacement map: a negative scale pulls pixels
// towards the edge, while the per-channel offset creates chromatic splitting.
uniform float u_distortion;
uniform float u_aberration;
uniform float u_edge_width;
uniform float u_edge_softness;

out vec4 frag_color;

vec2 sample_offset(vec2 uv, float scale, float red_map, float blue_map) {
  return clamp(
    uv + vec2(
      (red_map - 0.5) * scale / u_size.x,
      (blue_map - 0.5) * scale / u_size.y
    ),
    vec2(0.0),
    vec2(1.0)
  );
}

vec4 blurred_sample(vec2 uv, float scale, float red_map, float blue_map) {
  vec2 p = sample_offset(uv, scale, red_map, blue_map);
  vec2 texel = 1.0 / u_size;
  vec4 center = texture(u_texture, p) * 0.42;
  vec4 horizontal = (
    texture(u_texture, clamp(p + vec2(texel.x * 1.35, 0.0), vec2(0.0), vec2(1.0))) +
    texture(u_texture, clamp(p - vec2(texel.x * 1.35, 0.0), vec2(0.0), vec2(1.0)))
  ) * 0.19;
  vec4 vertical = (
    texture(u_texture, clamp(p + vec2(0.0, texel.y * 1.35), vec2(0.0), vec2(1.0))) +
    texture(u_texture, clamp(p - vec2(0.0, texel.y * 1.35), vec2(0.0), vec2(1.0)))
  ) * 0.10;
  return center + horizontal + vertical;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / u_size;

  // The generated Liquify map is neutral gray in the centre and transitions
  // to red horizontally and blue vertically only across the rounded rim.
  float edge_distance = min(
    min(uv.x, 1.0 - uv.x),
    min(uv.y, 1.0 - uv.y)
  );
  float edge = 1.0 - smoothstep(
    u_edge_width,
    u_edge_width + u_edge_softness,
    edge_distance
  );
  edge = pow(edge, 1.15);

  // A shallow lens bulge makes the background visibly expand at the rim,
  // instead of limiting the effect to a barely visible colour fringe.
  vec2 lens_uv = clamp(
    uv + (uv - 0.5) * edge * 0.085,
    vec2(0.0),
    vec2(1.0)
  );

  float red_map = mix(0.5, 1.0 - uv.x, edge);
  float blue_map = mix(0.5, uv.y, edge);

  vec4 red_layer = blurred_sample(
    lens_uv,
    u_distortion,
    red_map,
    blue_map
  );
  vec4 green_layer = blurred_sample(
    lens_uv,
    u_distortion + u_aberration,
    red_map,
    blue_map
  );
  vec4 blue_layer = blurred_sample(
    lens_uv,
    u_distortion + u_aberration * 1.65,
    red_map,
    blue_map
  );

  frag_color = vec4(
    red_layer.r,
    green_layer.g,
    blue_layer.b,
    max(red_layer.a, max(green_layer.a, blue_layer.a))
  );
}
