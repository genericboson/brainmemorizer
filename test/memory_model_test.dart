import 'package:brainmemorizer/app_state.dart';
import 'package:brainmemorizer/memory_model.dart';
import 'package:brainmemorizer/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MemoryModel', () {
    test('review is scheduled when recall drops to the target', () {
      final interval = MemoryModel.reviewInterval(1.0, 1.0);
      final days = interval.inSeconds / Duration.secondsPerDay;
      expect(
        MemoryModel.recallProbability(days, 1.0, 1.0),
        closeTo(MemoryModel.targetRetention, 0.001),
      );
    });

    test('failing shrinks the factor, succeeding grows it', () {
      final days =
          MemoryModel.reviewInterval(1.0, 1.0).inSeconds /
          Duration.secondsPerDay;
      final down = MemoryModel.adjustFactor(
        1.0,
        elapsedDays: days,
        stability: 1.0,
        recalled: false,
      );
      final up = MemoryModel.adjustFactor(
        1.0,
        elapsedDays: days,
        stability: 1.0,
        recalled: true,
      );
      expect(down, lessThan(1.0));
      expect(up, greaterThan(1.0));
    });

    test('factor settles where the success rate matches the target', () {
      // 평균보다 기억력이 절반인 사용자: 실제 기억 확률은 exp(-t / (S * 0.5)).
      // 예정된 간격마다 복습하며 기대 결과로 배율을 조정한다.
      var factor = 1.0;
      for (var i = 0; i < 2000; i++) {
        final days =
            MemoryModel.reviewInterval(1.0, factor).inSeconds /
            Duration.secondsPerDay;
        final trueRecall = MemoryModel.recallProbability(days, 1.0, 0.5);
        final up = MemoryModel.adjustFactor(
          factor,
          elapsedDays: days,
          stability: 1.0,
          recalled: true,
        );
        final down = MemoryModel.adjustFactor(
          factor,
          elapsedDays: days,
          stability: 1.0,
          recalled: false,
        );
        // 로그 공간에서 기대값만큼 이동한다.
        factor =
            factor *
            (trueRecall * (up / factor) + (1 - trueRecall) * (down / factor));
      }
      expect(factor, closeTo(0.5, 0.05));
    });

    test('factor stays within bounds', () {
      var factor = 1.0;
      for (var i = 0; i < 200; i++) {
        factor = MemoryModel.adjustFactor(
          factor,
          elapsedDays: 0.3,
          stability: 1.0,
          recalled: false,
        );
      }
      expect(factor, MemoryModel.minFactor);
    });
  });

  test('isCorrectAnswer ignores case and whitespace', () {
    expect(isCorrectAnswer(' 서울 특별시 ', '서울특별시'), isTrue);
    expect(isCorrectAnswer('Paris', 'paris'), isTrue);
    expect(isCorrectAnswer('부산', '서울'), isFalse);
  });

  group('AppState.recordAnswer', () {
    late AppState state;
    late StudyCard card;
    final t0 = DateTime(2026, 1, 1, 9);

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      state = await AppState.load();
      final category = state.addCategory('수도');
      state.addCard(category.id, '프랑스의 수도', '파리');
      card = state.cards.single;
    });

    test('first correct answer schedules the average interval', () {
      state.recordAnswer(
        card,
        correct: true,
        failedThisSession: false,
        now: t0,
      );
      expect(card.stability, MemoryModel.initialStability);
      expect(card.dueAt, t0.add(MemoryModel.reviewInterval(1.0, 1.0)));
      expect(state.memoryFactor, 1.0);
    });

    test('a later successful review grows stability', () {
      state.recordAnswer(
        card,
        correct: true,
        failedThisSession: false,
        now: t0,
      );
      state.recordAnswer(
        card,
        correct: true,
        failedThisSession: false,
        now: card.dueAt,
      );
      expect(
        card.stability,
        MemoryModel.initialStability * MemoryModel.stabilityGrowth,
      );
      expect(state.memoryFactor, greaterThan(1.0));
    });

    test('forgetting shortens intervals for the user', () {
      state.recordAnswer(
        card,
        correct: true,
        failedThisSession: false,
        now: t0,
      );
      final review = card.dueAt;
      state.recordAnswer(
        card,
        correct: false,
        failedThisSession: false,
        now: review,
      );
      expect(state.memoryFactor, lessThan(1.0));
      expect(card.isDue(review), isTrue);
      // 같은 학습에서 다시 맞혀도 배율과 안정도는 그대로다.
      final factor = state.memoryFactor;
      final stability = card.stability;
      state.recordAnswer(
        card,
        correct: true,
        failedThisSession: true,
        now: review.add(const Duration(minutes: 1)),
      );
      expect(state.memoryFactor, factor);
      expect(card.stability, stability);
    });

    test('data survives reload', () async {
      state.recordAnswer(
        card,
        correct: true,
        failedThisSession: false,
        now: t0,
      );
      final reloaded = await AppState.load();
      expect(reloaded.categories.single.name, '수도');
      expect(reloaded.cards.single.dueAt, card.dueAt);
    });
  });
}
