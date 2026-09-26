import 'dart:convert';

import 'package:brainmemorizer/app_state.dart';
import 'package:brainmemorizer/models.dart';
import 'package:brainmemorizer/services/wiki_collector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sampleHtml = '''
<div class="mw-parser-output">
<p><b>서울특별시</b>는 <a href="/wiki/%EB%8C%80%ED%95%9C%EB%AF%BC%EA%B5%AD" title="대한민국">대한민국</a>의 <a href="/wiki/%EC%88%98%EB%8F%84" title="수도">수도</a>이자 최대 도시이다.<sup id="cite_ref-1" class="reference"><a href="#cite_note-1">[1]</a></sup> 한반도 중앙에 있으며 <a href="/wiki/%ED%95%9C%EA%B0%95" title="한강">한강</a>이 시내를 가로질러 흐른다.</p>
<p>조선 시대에는 <a href="/wiki/%ED%95%9C%EC%96%91" title="한양">한양</a>이라 불렸으며, <a href="/wiki/%EA%B2%BD%EB%B3%B5%EA%B6%81" title="경복궁">경복궁</a>을 비롯한 궁궐이 남아 있다. <a href="/wiki/%ED%95%9C%EA%B0%95" title="한강">한강</a>은 남북을 나누는 기준이 된다.</p>
<p>인구는 <a href="/wiki/2020%EB%85%84" title="2020년">2020년</a> 기준 약 970만 명이다. <a href="/wiki/%ED%8C%8C%EC%9D%BC:Seoul.jpg">사진</a>도 있다.</p>
<p>짧다 <a href="/wiki/%EC%A7%A7%EC%9D%8C" title="짧음">짧음</a>.</p>
</div>
''';

/// 위키백과처럼 UTF-8 바이트로 JSON 을 돌려준다 (charset 헤더는 일부러 뺀다).
http.Response jsonResponse(Object json) =>
    http.Response.bytes(utf8.encode(jsonEncode(json)), 200);

http.Client fakeClient({bool found = true}) => MockClient((request) async {
  final action = request.url.queryParameters['action'];
  if (action == 'query') {
    return jsonResponse({
      'query': {
        'search': found
            ? [
                {'title': '서울특별시'},
              ]
            : [],
      },
    });
  }
  expect(request.url.queryParameters['page'], '서울특별시');
  return jsonResponse({
    'parse': {'title': '서울특별시', 'text': sampleHtml},
  });
});

void main() {
  group('WikiCollector.extractCards', () {
    final cards = WikiCollector.extractCards(sampleHtml, title: '서울특별시');
    final byAnswer = {for (final c in cards) c.answer: c};

    test('makes a cloze question for each linked term', () {
      expect(byAnswer.keys, containsAll(['대한민국', '수도', '한강', '한양', '경복궁']));
      expect(
        byAnswer['수도']!.question,
        '빈칸에 들어갈 말은? 서울특별시는 대한민국의 ____이자 최대 도시이다.',
      );
    });

    test('drops citations, numbers, file links and short sentences', () {
      expect(byAnswer['수도']!.question, isNot(contains('[1]')));
      expect(byAnswer.keys, isNot(contains('2020년')));
      expect(
        WikiCollector.extractCards(
          '<p>이 문서는 <a href="/wiki/x">1897년</a>부터 <a href="/wiki/y">19세기</a>까지의 긴 역사를 다룬다.</p>',
          title: 't',
        ),
        isEmpty,
      );
      expect(byAnswer.keys, isNot(contains('사진')));
      expect(byAnswer.keys, isNot(contains('짧음')));
    });

    test('ranks frequent, early terms as more important', () {
      // 한강은 두 번 언급되고 첫 문단에 나오므로 가장 중요하다.
      expect(cards.first.answer, '한강');
      expect(byAnswer['한강']!.grade, 1);
      expect(byAnswer['경복궁']!.grade, greaterThan(byAnswer['대한민국']!.grade));
      for (final c in cards) {
        expect(c.grade, inInclusiveRange(1, subcategoryCount));
      }
    });

    test('grades are cumulative: subcategory N holds grades 1..N', () {
      final grades = cards.map((c) => c.grade).toList();
      for (var n = 1; n <= subcategoryCount; n++) {
        final inSub = grades.where((g) => g <= n).length;
        final inPrev = grades.where((g) => g <= n - 1).length;
        expect(inSub, greaterThanOrEqualTo(inPrev));
      }
      expect(grades.where((g) => g <= subcategoryCount).length, cards.length);
    });
  });

  group('WikiCollector.collect', () {
    test('searches for the page and returns its cards', () async {
      final result = await WikiCollector(client: fakeClient()).collect('서울');
      expect(result.title, '서울특별시');
      expect(result.cards.map((c) => c.answer), contains('한강'));
    });

    test('reports a missing page', () async {
      expect(
        () => WikiCollector(client: fakeClient(found: false)).collect('없는주제'),
        throwsA(isA<CollectException>()),
      );
    });
  });

  group('AppState subcategories', () {
    late AppState state;
    late String categoryId;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      state = await AppState.load();
      categoryId = state.addCategory('서울').id;
    });

    test('addCards stores grades and skips duplicate questions', () {
      final collected = WikiCollector.extractCards(sampleHtml, title: '서울특별시');
      expect(state.addCards(categoryId, collected), collected.length);
      expect(state.addCards(categoryId, collected), 0);
      expect(state.cardsIn(categoryId).length, collected.length);
    });

    test('subcategory N contains grades up to N', () {
      state.addCard(categoryId, 'q1', 'a1', grade: 1);
      state.addCard(categoryId, 'q3', 'a3', grade: 3);
      state.addCard(categoryId, 'q10', 'a10', grade: 10);
      expect(state.cardsIn(categoryId, subcategory: 1).length, 1);
      expect(state.cardsIn(categoryId, subcategory: 3).length, 2);
      expect(state.cardsIn(categoryId, subcategory: 9).length, 2);
      expect(state.cardsIn(categoryId).length, 3);
      expect(
        state.dueCardsIn(categoryId, DateTime.now(), subcategory: 2).length,
        1,
      );
    });

    test('learnedCount counts reviewed cards that are not due', () {
      state.addCard(categoryId, 'q1', 'a1');
      state.addCard(categoryId, 'q2', 'a2');
      final now = DateTime(2026, 1, 1);
      final cards = state.cardsIn(categoryId);
      expect(AppState.learnedCount(cards, now), 0);
      state.recordAnswer(
        cards[0],
        correct: true,
        failedThisSession: false,
        now: now,
      );
      expect(AppState.learnedCount(cards, now), 1);
      expect(AppState.learnedCount(cards, cards[0].dueAt), 0);
    });

    test('old data without a grade loads as grade 1', () async {
      SharedPreferences.setMockInitialValues({
        'brainmemorizer.data.v1': jsonEncode({
          'memoryFactor': 1.0,
          'categories': [
            {'id': 'c', 'name': '옛날'},
          ],
          'cards': [
            {
              'id': 'k',
              'categoryId': 'c',
              'question': 'q',
              'answer': 'a',
              'stability': 1.0,
              'reviewCount': 0,
              'lapseCount': 0,
              'lastReviewedAt': null,
              'dueAt': '2026-01-01T00:00:00.000',
            },
          ],
        }),
      });
      final loaded = await AppState.load();
      expect(loaded.cards.single.grade, 1);
    });
  });
}
