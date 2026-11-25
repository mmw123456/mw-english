import 'package:flutter_test/flutter_test.dart';
import 'package:mw_english/app/app.dart';

void main() {
  testWidgets('四个 Tab 都在，默认停在「学习」', (WidgetTester tester) async {
    await tester.pumpWidget(const MwEnglishApp());

    expect(find.text('词库'), findsOneWidget);
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('开始学习'), findsOneWidget);
  });

  testWidgets('切到词库页', (WidgetTester tester) async {
    await tester.pumpWidget(const MwEnglishApp());

    await tester.tap(find.text('词库'));
    await tester.pumpAndSettle();

    expect(find.text('我的词表'), findsOneWidget);
    expect(find.text('离线词典'), findsOneWidget);
  });
}
