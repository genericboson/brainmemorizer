import 'package:brainmemorizer/app_state.dart';
import 'package:brainmemorizer/screens/settings_page.dart';
import 'package:brainmemorizer/services/sync_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'sync_service_test.dart' show FakeAuthGateway;

void main() {
  testWidgets('log in from the settings page, toggle auto login, log out', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final state = await AppState.load();
    final auth = FakeAuthGateway(accounts: const {'me@test.com': 'secret123'});
    final sync = SyncService(
      state: state,
      firestore: FakeFirebaseFirestore(),
      prefs: prefs,
      auth: auth,
    );
    await sync.start();
    await tester.pumpWidget(
      MaterialApp(home: SettingsPage(startupSettings: null, sync: sync)),
    );

    expect(find.text('로그인'), findsOneWidget);
    expect(find.text('회원가입'), findsOneWidget);
    expect(find.text('자동 로그인'), findsOneWidget);

    // 틀린 비밀번호
    await tester.enterText(
      find.widgetWithText(TextField, '이메일'),
      'me@test.com',
    );
    await tester.enterText(find.widgetWithText(TextField, '비밀번호'), 'wrong');
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.text('이메일 또는 비밀번호가 맞지 않습니다.'), findsOneWidget);

    // 맞는 비밀번호
    await tester.enterText(find.widgetWithText(TextField, '비밀번호'), 'secret123');
    await tester.tap(find.text('로그인'));
    await tester.pumpAndSettle();
    expect(find.text('로그인됨: me@test.com'), findsOneWidget);
    expect(find.text('로그아웃'), findsOneWidget);

    // 자동 로그인 끄기
    expect(sync.autoLogin, isTrue);
    await tester.tap(find.text('자동 로그인'));
    await tester.pumpAndSettle();
    expect(sync.autoLogin, isFalse);

    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(find.text('로그인'), findsOneWidget);
    expect(auth.currentUser, isNull);
  });
}
