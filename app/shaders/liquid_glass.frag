#version 460 core
#include <flutter/runtime_effect.glsl>

// 液态玻璃真折射（v0.7.1）。
//
// 风格来源 guanmo-ai/design-style 的 014 液态玻璃，规则按原文落实：
//   01 只在 bevel 一圈做位移，中间保持平、字可读；中间整体放大 3–6%；
//      边缘色散约 6%（红绿蓝分开折一点点）。
//   02 bevel 厚度按层级：列表行 12 / 按钮 26 / 浮层 44px（Dart 侧按尺寸选档后传入）。
//
// 作为 ImageFilter.shader 使用：第一个 uniform 必须是 vec2（引擎写入输入纹理
// 尺寸），第一个 sampler2D 由引擎绑定为「玻璃背后的画面」。
uniform vec2 uSize;
uniform float uRadius;
uniform float uBevel;
uniform float uMagnify;
uniform float uDispersion;
uniform sampler2D uBackdrop;

out vec4 fragColor;

// bevel 内最大采样位移，占 bevel 厚度的比例。
const float kEdgeBend = 0.62;

// 圆角矩形有符号距离：内部为负，边缘为 0。
float sdRoundRect(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + vec2(r);
  return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  // Impeller 的 GLES 后端 y 轴朝下，不翻会上下颠倒。
  uv.y = 1.0 - uv.y;
#endif

  vec2 halfSize = uSize * 0.5;
  float radius = min(uRadius, min(halfSize.x, halfSize.y));
  // 小胶囊也要留出中央平坦区：bevel 最多占短边的 35%，中间 30% 不弯。
  float bevel = min(uBevel, min(halfSize.x, halfSize.y) * 0.7);
  vec2 p = (uv - 0.5) * uSize;

  // edge：0 = bevel 内边界（含中心），1 = 最外一圈。圈外恒为 0。
  float sd = sdRoundRect(p, halfSize, radius);
  float edge = clamp(1.0 + sd / max(bevel, 0.001), 0.0, 1.0);
  // 平方让弯折集中在最外 1/3，内边界平滑收住。
  float bend = edge * edge;

  // 圆角矩形的外法线（SDF 梯度的近似）。远离边缘时 q 全为负，
  // 法线取 0；那时 bend 也是 0，乘起来仍是 0。
  vec2 q = abs(p) - halfSize + vec2(radius);
  vec2 n = sign(p) * max(q, vec2(0.0));
  n = length(n) > 0.0001 ? normalize(n) : vec2(0.0);

  // 014 规则 01：中间整体放大 3–6%（取 4.5%），中心点位移为 0，
  // 字仍在原位、只是略大，不会被折碎。
  vec2 magnified = (uv - 0.5) / uMagnify + 0.5;

  // 边缘位移：沿法线向内折，幅度按 bevel 计算；像素 → UV 除以 uSize。
  vec2 bendUv = -n * bend * bevel * kEdgeBend / uSize;

  // 色散 6%：红 / 蓝各偏一半，绿在中间，红蓝之间差 6%。
  vec2 spread = bendUv * (uDispersion * 0.5);

  vec3 color;
  color.r = texture(uBackdrop, magnified + bendUv + spread).r;
  color.g = texture(uBackdrop, magnified + bendUv).g;
  color.b = texture(uBackdrop, magnified + bendUv - spread).b;

  fragColor = vec4(color, 1.0);
}
