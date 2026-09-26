import 'package:brainmemorizer/app_state.dart';
import 'package:brainmemorizer/services/review_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppState state;
  late String categoryId;
  late DateTime now;
  final calls = <int>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = await AppState.load();
    categoryId = state.addCategory('c').id;
    // 새 카드는 실제 시각으로 dueAt 이 찍히므로, 테스트 시계는 그보다 조금 뒤로 둔다.
    now = DateTime.now().add(const Duration(seconds: 1));
    calls.clear();
  });

  ReviewScheduler scheduler() =>
      ReviewScheduler(state, onDue: calls.add, clock: () => now);

  test('announces due cards once, not again on later checks', () {
    state.addCard(categoryId, 'q1', 'a1');
    state.addCard(categoryId, 'q2', 'a2');
    final s = scheduler();
    expect(s.check(), 2);
    expect(calls, [2]);
    expect(s.dueCount, 2);
    expect(s.check(), 0);
    expect(calls, [2]);
  });

  test('announces again only after the card was reviewed and comes due', () {
    state.addCard(categoryId, 'q1', 'a1');
    final card = state.cards.single;
    final s = scheduler();
    s.check();

    state.recordAnswer(card, correct: true, failedThisSession: false, now: now);
    expect(s.check(), 0);
    expect(s.dueCount, 0);
    expect(s.nextDueAt(), card.dueAt);

    now = card.dueAt;
    expect(s.check(), 1);
    expect(calls, [1, 1]);
  });

  test('a newly added card triggers a check through the state listener', () {
    final s = scheduler()..start();
    addTearDown(s.dispose);
    state.addCard(categoryId, 'q1', 'a1');
    expect(calls, [1]);
  });
}
