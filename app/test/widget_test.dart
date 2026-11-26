import 'package:flutter_test/flutter_test.dart';
import 'package:mw_english/app/app.dart';

/// 注意：widget 测试环境没有 sqflite 的 platform channel，
/// 词库页与学习页会走到「数据读不到」的分支。
/// 所以这里只断言与数据库无关的稳定元素（Tab、固定文案、搜索框）。
void main() {
  testWidgets('四个 Tab 都在，默认停在「学习」', (WidgetTester tester) async {
    await tester.pumpWidget(const MwEnglishApp());

    expect(find.text('词库'), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('开始学习'), findsOneWidget);
  });

  testWidgets('学习页显示每日目标 30 词', (WidgetTester tester) async {
    await tester.pumpWidget(const MwEnglishApp());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('目标 30 词'), findsOneWidget);
    expect(find.text('/ 30'), findsOneWidget);
  });

  testWidgets('切到词库页', (WidgetTester tester) async {
    await tester.pumpWidget(const MwEnglishApp());

    await tester.tap(find.text('词库'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 搜索框属于词库页自身，不依赖数据库是否可用
    expect(find.text('查词，中英均可'), findsOneWidget);
  });

  testWidgets('我的页显示学习计划每日 30 词', (WidgetTester tester) async {
    await tester.pumpWidget(const MwEnglishApp());

    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('每日 30 词'), findsOneWidget);
  });
}
