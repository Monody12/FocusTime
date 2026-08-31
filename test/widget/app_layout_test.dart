import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/app.dart';
import 'package:focus_my_time/core/services/timer_notification_service.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';

void main() {
  testWidgets('Web 提醒为空或显示时主界面都不会塌缩', (tester) async {
    final reminder = ValueNotifier<WebReminder?>(null);
    addTearDown(reminder.dispose);

    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Stack(
              key: const Key('application-stack'),
              children: [
                const Positioned.fill(
                  child: ColoredBox(
                    key: Key('application-body'),
                    color: Colors.white,
                  ),
                ),
                WebReminderOverlay(
                  topInset: 0,
                  isMobile: false,
                  reminderListenable: reminder,
                  onDismiss: () => reminder.value = null,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('application-stack'))),
      const Size(1200, 800),
    );
    expect(
      tester.getSize(find.byKey(const Key('application-body'))),
      const Size(1200, 800),
    );

    reminder.value = const WebReminder(title: '任务提醒', body: '测试任务');
    await tester.pump();
    expect(find.text('任务提醒'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('application-body'))),
      const Size(1200, 800),
    );

    await tester.tap(find.byTooltip('关闭提醒'));
    await tester.pump();
    expect(reminder.value, isNull);
    expect(
      tester.getSize(find.byKey(const Key('application-body'))),
      const Size(1200, 800),
    );
  });

  testWidgets('回归夹具能复现零尺寸非定位子项导致的 Stack 塌缩', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Stack(
              key: Key('legacy-stack'),
              children: [
                Positioned.fill(child: ColoredBox(color: Colors.white)),
                SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byKey(const Key('legacy-stack'))), Size.zero);
  });
}
