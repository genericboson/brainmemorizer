import 'dart:convert';

import 'package:brainmemorizer/app_state.dart';
import 'package:brainmemorizer/main.dart';
import 'package:brainmemorizer/screens/input_tab.dart';
import 'package:brainmemorizer/services/wiki_collector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> freshState() async {
  SharedPreferences.setMockInitialValues({});
  return AppState.load();
}

Future<void> createCategory(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('카테고리 추가'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, name);
  await tester.tap(find.text('만들기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('add a category and card, then answer it in the study tab', (
    tester,
  ) async {
    final state = await freshState();
    await tester.pumpWidget(BrainMemorizerApp(state: state));

    expect(find.text('학습데이터 주입'), findsOneWidget);
    expect(find.text('학습'), findsOneWidget);

    await createCategory(tester, '수도');

    // 학습데이터 넣기 (기본 서브카테고리 1)
    await tester.enterText(find.widgetWithText(TextField, '질문'), '프랑스의 수도');
    await tester.enterText(find.widgetWithText(TextField, '정답 (단답형)'), '파리');
    await tester.tap(find.text('서브카테고리 1에 추가'));
    await tester.pumpAndSettle();
    expect(find.text('정답: 파리'), findsOneWidget);
    expect(find.text("'수도' 전체 1개 · 서브카테고리 1: 1개"), findsOneWidget);

    // 학습 탭: 기본 서브카테고리 10, 진행도 0%
    await tester.tap(find.text('학습'));
    await tester.pumpAndSettle();
    expect(find.text("'수도' 전체: 학습 완료 0/1 (0%)"), findsOneWidget);
    expect(find.text('서브카테고리 10: 학습 완료 0/1 (0%)'), findsOneWidget);
    expect(find.text('지금 복습할 문제 1개'), findsOneWidget);
    await tester.tap(find.text('학습 시작'));
    await tester.pumpAndSettle();

    expect(find.text('프랑스의 수도'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '정답 입력'), '파리');
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    expect(find.text('정답입니다!'), findsOneWidget);

    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(find.text('학습 완료!'), findsOneWidget);
    expect(state.cards.single.reviewCount, 1);

    // 돌아오면 진행도가 100% 로 바뀐다.
    await tester.tap(find.text('돌아가기'));
    await tester.pumpAndSettle();
    expect(find.text('서브카테고리 10: 학습 완료 1/1 (100%)'), findsOneWidget);
  });

  testWidgets('auto-collect fills the category from the web', (tester) async {
    final state = await freshState();
    // 위키백과처럼 UTF-8 바이트로 JSON 을 돌려준다.
    http.Response jsonResponse(Object json) =>
        http.Response.bytes(utf8.encode(jsonEncode(json)), 200);
    final client = MockClient((request) async {
      if (request.url.queryParameters['action'] == 'query') {
        return jsonResponse({
          'query': {
            'search': [
              {'title': '광합성 (생물학)'},
            ],
          },
        });
      }
      return jsonResponse({
        'parse': {
          'text':
              '<p>광합성은 <a href="/wiki/A" title="식물">식물</a>이 '
              '<a href="/wiki/B" title="빛에너지">빛에너지</a>를 화학 에너지로 바꾸는 과정이다.</p>',
        },
      });
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InputTab(
            state: state,
            collector: WikiCollector(client: client),
          ),
        ),
      ),
    );
    await createCategory(tester, '광합성');

    await tester.tap(find.text('학습 데이터 자동 수집'));
    await tester.pumpAndSettle();

    expect(
      find.text("'광합성' (위키백과 '광합성 (생물학)' 문서) 학습데이터 2개를 추가했습니다."),
      findsOneWidget,
    );
    expect(state.cardsIn(state.categories.single.id).length, 2);
    // 기본 서브카테고리 1 에는 1등급 카드만 보인다.
    expect(find.text("'광합성' 전체 2개 · 서브카테고리 1: 1개"), findsOneWidget);
  });
}
