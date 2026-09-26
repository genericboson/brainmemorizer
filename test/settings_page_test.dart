import 'package:brainmemorizer/app_state.dart';
import 'package:brainmemorizer/main.dart';
import 'package:brainmemorizer/services/startup_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeStartupSettings implements StartupSettings {
  FakeStartupSettings({this.isSupported = true});

  @override
  final bool isSupported;

  @override
  bool isEnabled = false;

  final List<bool> calls = [];

  @override
  bool setEnabled(bool enabled) {
    calls.add(enabled);
    isEnabled = enabled;
    return true;
  }
}

void main() {
  Future<AppState> freshState() async {
    SharedPreferences.setMockInitialValues({});
    return AppState.load();
  }

  testWidgets(
    'gear icon opens settings and the switch toggles launch at login',
    (tester) async {
      final startup = FakeStartupSettings();
      await tester.pumpWidget(
        BrainMemorizerApp(state: await freshState(), startupSettings: startup),
      );

      await tester.tap(find.byTooltip('설정'));
      await tester.pumpAndSettle();
      expect(find.text('설정'), findsOneWidget);
      expect(find.text('Windows 시작 시 자동 실행'), findsOneWidget);

      final toggle = find.byType(SwitchListTile);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(startup.calls, [true]);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(startup.calls, [true, false]);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    },
  );

  testWidgets('switch is disabled where launch at login is unsupported', (
    tester,
  ) async {
    await tester.pumpWidget(
      BrainMemorizerApp(
        state: await freshState(),
        startupSettings: FakeStartupSettings(isSupported: false),
      ),
    );
    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();

    expect(find.text('이 기기에서는 지원하지 않습니다.'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
  });
}
