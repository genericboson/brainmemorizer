import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_model.dart';
import 'models.dart';
import 'services/wiki_collector.dart';

/// 카테고리, 학습 카드, 사용자별 망각곡선 배율을 보관하고 저장한다.
class AppState extends ChangeNotifier {
  AppState._(this._prefs);

  static const _storageKey = 'brainmemorizer.data.v1';

  final SharedPreferences _prefs;
  final List<StudyCategory> categories = [];
  final List<StudyCard> cards = [];

  /// 사용자 망각곡선 배율. 1.0 = 평균.
  double memoryFactor = 1.0;

  int _idCounter = 0;

  static Future<AppState> load() async {
    final state = AppState._(await SharedPreferences.getInstance());
    final raw = state._prefs.getString(_storageKey);
    if (raw != null) {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      state.memoryFactor = (json['memoryFactor'] as num).toDouble();
      state.categories.addAll(
        (json['categories'] as List).map(
          (e) => StudyCategory.fromJson(e as Map<String, dynamic>),
        ),
      );
      state.cards.addAll(
        (json['cards'] as List).map(
          (e) => StudyCard.fromJson(e as Map<String, dynamic>),
        ),
      );
    }
    return state;
  }

  String _newId() => '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  StudyCategory? categoryById(String? id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// 카테고리의 서브카테고리 [subcategory] 에 든 카드(등급이 그 이하인 카드).
  List<StudyCard> cardsIn(
    String categoryId, {
    int subcategory = subcategoryCount,
  }) => cards
      .where((c) => c.categoryId == categoryId && c.grade <= subcategory)
      .toList();

  /// 지금 복습할 카드. 복습 시점이 오래 지난 것부터.
  List<StudyCard> dueCardsIn(
    String categoryId,
    DateTime now, {
    int subcategory = subcategoryCount,
  }) =>
      cardsIn(
          categoryId,
          subcategory: subcategory,
        ).where((c) => c.isDue(now)).toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));

  /// 한 번 이상 맞혀서 아직 복습 시점이 오지 않은 카드 수.
  static int learnedCount(List<StudyCard> cards, DateTime now) =>
      cards.where((c) => !c.isNew && !c.isDue(now)).length;

  StudyCategory addCategory(String name) {
    final category = StudyCategory(id: _newId(), name: name);
    categories.add(category);
    _saveAndNotify();
    return category;
  }

  void deleteCategory(String id) {
    categories.removeWhere((c) => c.id == id);
    cards.removeWhere((c) => c.categoryId == id);
    _saveAndNotify();
  }

  void addCard(
    String categoryId,
    String question,
    String answer, {
    int grade = 1,
  }) {
    cards.add(_newCard(categoryId, question, answer, grade));
    _saveAndNotify();
  }

  /// 여러 카드를 한 번에 넣는다. 같은 질문이 이미 있으면 건너뛰고,
  /// 실제로 추가한 개수를 돌려준다.
  int addCards(String categoryId, Iterable<CollectedCard> collected) {
    final existing = cardsIn(categoryId).map((c) => c.question).toSet();
    var added = 0;
    for (final c in collected) {
      if (!existing.add(c.question)) continue;
      cards.add(_newCard(categoryId, c.question, c.answer, c.grade));
      added++;
    }
    if (added > 0) _saveAndNotify();
    return added;
  }

  StudyCard _newCard(
    String categoryId,
    String question,
    String answer,
    int grade,
  ) => StudyCard(
    id: _newId(),
    categoryId: categoryId,
    question: question,
    answer: answer,
    grade: grade.clamp(1, subcategoryCount),
    dueAt: DateTime.now(),
  );

  void deleteCard(String id) {
    cards.removeWhere((c) => c.id == id);
    _saveAndNotify();
  }

  /// 복습 결과를 반영해 카드의 다음 복습 시점과 사용자 배율을 갱신한다.
  ///
  /// [failedThisSession] 은 이번 학습에서 이미 한 번 틀린 카드인지를 뜻한다.
  /// 그런 카드의 재시도는 방금 정답을 본 직후라 망각곡선 정보가 없으므로
  /// 사용자 배율과 안정도를 바꾸지 않는다.
  void recordAnswer(
    StudyCard card, {
    required bool correct,
    required bool failedThisSession,
    DateTime? now,
  }) {
    now ??= DateTime.now();
    final last = card.lastReviewedAt;
    final isRealReview = last != null && !failedThisSession;

    if (isRealReview) {
      final elapsedDays =
          now.difference(last).inSeconds / Duration.secondsPerDay;
      memoryFactor = MemoryModel.adjustFactor(
        memoryFactor,
        elapsedDays: elapsedDays,
        stability: card.stability,
        recalled: correct,
      );
    }

    if (correct) {
      if (isRealReview) card.stability *= MemoryModel.stabilityGrowth;
      card.dueAt = now.add(
        MemoryModel.reviewInterval(card.stability, memoryFactor),
      );
    } else {
      card.lapseCount++;
      if (isRealReview) {
        card.stability = math.max(
          card.stability * MemoryModel.lapseFactor,
          MemoryModel.minStability,
        );
      }
      card.dueAt = now;
    }

    card.reviewCount++;
    card.lastReviewedAt = now;
    _saveAndNotify();
  }

  void _saveAndNotify() {
    _prefs.setString(
      _storageKey,
      jsonEncode({
        'memoryFactor': memoryFactor,
        'categories': categories.map((c) => c.toJson()).toList(),
        'cards': cards.map((c) => c.toJson()).toList(),
      }),
    );
    notifyListeners();
  }
}
