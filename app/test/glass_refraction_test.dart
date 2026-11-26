import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mw_english/app/shell/shell_padding.dart';
import 'package:mw_english/app/theme/app_theme.dart';
import 'package:mw_english/app/theme/liquid_glass.dart';
import 'package:mw_english/features/profile/profile_page.dart';

/// v0.7.1 真折射的验收测试。
///
/// 断言全部取自需求原文（014 规则 01 / 02 + 本版要求），不从实现里抄常量：
/// - 玻璃边缘真的折射：只在 bevel 一圈做位移，中间保持平、字可读；
/// - 中间整体放大 3–6%，边缘色散约 6%；
/// - bevel 厚度按层级：列表行 12 / 按钮 26 / 浮层 44px；
/// - shader 加载失败静默回落，不闪退、不白屏、不断言；
/// - 各页滚动内容底部内边距存在，最后一行不被悬浮 Tab 栏压住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(GlassRefraction.debugReset);

  group('shader 文件', () {
    test('存在且能编译', () async {
      final file = File('shaders/liquid_glass.frag');
      expect(file.existsSync(), isTrue,
          reason: '真折射要 .frag 文件，不能只在 Dart 里假装');

      final program = await ui.FragmentProgram.fromAsset(
        GlassRefraction.asset,
      );
      final shader = program.fragmentShader();
      expect(shader, isNotNull);
      shader.dispose();
    });

    test('第一个 uniform 是 vec2、且带 sampler（ImageFilter.shader 的硬要求）',
        () {
      final source = File('shaders/liquid_glass.frag').readAsStringSync();
      final uniforms = RegExp(r'^uniform\s+(\w+)\s+(\w+);', multiLine: true)
          .allMatches(source)
          .map((m) => (type: m.group(1), name: m.group(2)))
          .toList();

      expect(uniforms.first.type, 'vec2',
          reason: 'ImageFilter.shader 要求首个 uniform 是 vec2，由引擎写尺寸');
      expect(uniforms.first.name, 'uSize');
      expect(
        uniforms.any((u) => u.type == 'sampler2D'),
        isTrue,
        reason: '没有 sampler 就采不到背后的东西，折射无从谈起',
      );
      expect(uniforms.map((u) => u.name), containsAll(<String>[
        'uBevel',
        'uMagnify',
        'uDispersion',
      ]));
    });

    test('shader 与 Dart 侧的位移系数一致（防止两套实现漂移）', () {
      final source = File('shaders/liquid_glass.frag').readAsStringSync();
      expect(source, contains('const float kEdgeBend = 0.62;'));
      expect(GlassRefraction.edgeBend, 0.62);
      expect(source, contains('#ifdef IMPELLER_TARGET_OPENGLES'),
          reason: 'GLES 后端 y 轴反转必须翻，否则折射上下颠倒');
    });
  });

  group('014 规则 01：位移只在 bevel 圈内，中心保持平', () {
    const size = Size(320, 200);
    const radius = 26.0;
    const bevel = GlassRefraction.bevelSheet;
    const halfHeight = 100.0;

    test('bevel 厚度按层级：列表行 12 / 按钮 26 / 浮层 44', () {
      expect(GlassRefraction.bevelList, 12);
      expect(GlassRefraction.bevelButton, 26);
      expect(GlassRefraction.bevelSheet, 44);

      expect(GlassRefraction.bevelFor(const Size(300, 40)),
          GlassRefraction.bevelList);
      expect(GlassRefraction.bevelFor(const Size(400, 100)),
          GlassRefraction.bevelButton);
      expect(GlassRefraction.bevelFor(const Size(320, 200)),
          GlassRefraction.bevelSheet);

      // 小胶囊也得有中央平坦区：实际 bevel 不超过短边的 35%。
      final tiny = GlassRefraction.bevelFor(const Size(120, 26));
      expect(tiny, lessThanOrEqualTo(26 * 0.35 + 1e-9));
    });

    test('中心点位移为 0 —— 字不会被折碎', () {
      final center = GlassRefraction.sample(
        p: Offset.zero,
        size: size,
        radius: radius,
        bevel: bevel,
      );
      expect(center.bend, Offset.zero);
      expect(center.offset, Offset.zero);
    });

    test('bevel 圈内才有边缘位移，圈外只有整体放大', () {
      // 沿垂直中线从中心走到最外：距边 > 44 的每一像素都不许弯。
      var firstBent = -1;
      for (var y = 0; y < halfHeight; y++) {
        final s = GlassRefraction.sample(
          p: Offset(0, y.toDouble()),
          size: size,
          radius: radius,
          bevel: bevel,
        );
        final distanceToEdge = halfHeight - y;
        if (distanceToEdge > bevel) {
          expect(s.bend, Offset.zero,
              reason: '距边 $distanceToEdge px 还在 bevel 圈外，不该有位移');
          expect(s.edge, 0);
        } else if (s.bend.distance > 0) {
          firstBent = firstBent == -1 ? y : firstBent;
        }
      }
      expect(firstBent, greaterThan(0), reason: 'bevel 圈内必须真的弯');
      expect(halfHeight - firstBent, lessThanOrEqualTo(bevel),
          reason: '第一处弯必须落在 bevel 圈内');
    });

    test('边缘位移朝内，不是朝外', () {
      // p = (0, 80)：距底边 20px，在 44 的 bevel 圈内。
      final s = GlassRefraction.sample(
        p: const Offset(0, 80),
        size: size,
        radius: radius,
        bevel: bevel,
      );
      expect(s.bend.distance, greaterThan(0));
      expect(s.bend.dy, lessThan(0),
          reason: '底边的弯折应把更靠内的背景折进来（向上）');
    });

    test('中间整体放大 3–6%，边缘色散约 6%', () {
      expect(GlassRefraction.magnify, inInclusiveRange(1.03, 1.06));
      expect(GlassRefraction.dispersion, 0.06);

      // 圈外的一点只有放大项：采样点比原位置更靠中心。
      final s = GlassRefraction.sample(
        p: const Offset(0, 55),
        size: size,
        radius: radius,
        bevel: bevel,
      );
      expect(s.bend, Offset.zero);
      expect(s.offset.dy, lessThan(0));
      expect(
        s.offset.dy.abs(),
        closeTo(55 * (1 - 1 / GlassRefraction.magnify), 1e-9),
      );
    });

    test('三档 bevel 的位移都只发生在自己那一圈', () {
      for (final bevel in <double>[
        GlassRefraction.bevelList,
        GlassRefraction.bevelButton,
        GlassRefraction.bevelSheet,
      ]) {
        final outside = GlassRefraction.sample(
          p: Offset(0, halfHeight - bevel - 1),
          size: size,
          radius: radius,
          bevel: bevel,
        );
        final inside = GlassRefraction.sample(
          p: Offset(0, halfHeight - bevel / 2),
          size: size,
          radius: radius,
          bevel: bevel,
        );
        expect(outside.bend, Offset.zero, reason: 'bevel=$bevel 圈外不该弯');
        expect(inside.bend.distance, greaterThan(0),
            reason: 'bevel=$bevel 圈内该弯');
      }
    });
  });

  group('加载失败静默回落', () {
    test('ensureLoaded 失败返回 null，不抛', () async {
      GlassRefraction.debugLoader =
          (_) async => throw StateError('shader 编译挂了');
      final program = await GlassRefraction.ensureLoaded();
      expect(program, isNull);
      expect(GlassRefraction.program, isNull);
    });

    testWidgets('回落时内容还在、不抛异常、近似玻璃照常渲染', (tester) async {
      GlassRefraction.debugLoader =
          (_) async => throw StateError('shader 编译挂了');

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: Center(child: GlassSurface(child: Text('玻璃'))),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('玻璃'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget,
          reason: '回落路径仍有 1.5px 磨砂');
    });
  });

  group('底部内边距（不被悬浮 Tab 栏压住）', () {
    testWidgets('口径 = 96 + 系统底部安全区', (tester) async {
      late EdgeInsets padding;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              viewPadding: EdgeInsets.only(bottom: 34),
            ),
            child: Builder(
              builder: (context) {
                padding = ShellPadding.scroll(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );

      expect(ShellPadding.bottomBase, 96);
      expect(padding.bottom, 130,
          reason: '96 只够条子本体；全面屏 34 的安全区必须加上');
      expect(padding.left, 20);
      expect(padding.top, 8);
    });

    testWidgets('页面真的用上了：我的页列表底部 = 130', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const MediaQuery(
            data: MediaQueryData(
              viewPadding: EdgeInsets.only(bottom: 34),
            ),
            child: ProfilePage(),
          ),
        ),
      );
      await tester.pump();

      final list = tester.widget<ListView>(find.byType(ListView));
      final padding = list.padding! as EdgeInsets;
      expect(padding.bottom, 130,
          reason: 'v0.7.0 写死 96 时，最后一行就是在这里被压住的');
    });
  });
}
