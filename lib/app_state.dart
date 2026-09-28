import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'memory_model.dart';
import 'models.dart';
import 'services/wiki_collector.dart';

/// 이 기기에서 일어난 변경. 동기화 서비스가 원격 저장소에 밀어 넣는다.
sealed class StateChange {
  const StateChange();
}

class CategoryUpserted extends StateChange {
  const CategoryUpserted(this.category);
  final StudyCategory category;
}

class CategoryDeleted extends StateChange {
  const CategoryDeleted(this.id, this.cardIds);
  final String id;
  final List<String> cardIds;
}

class CardUpserted extends StateChange {
  const CardUpserted(this.card);
  final StudyCard card;
}

class CardDeleted extends StateChange {
  const CardDeleted(this.id);
  final String id;
}

class ProfileChanged extends StateChange {
  const ProfileChanged(this.memoryFactor, this.updatedAt);
  final double memoryFactor;
  final DateTime updatedAt;
}

/// 카테고리, 학습 카드, 사용자별 망각곡선 배율을 보관하고 저장한다.
///
/// 이 기기의 변경은 [changes] 로 흘러나가고, 다른 기기의 변경은
/// `applyRemote*` 로 들어온다. 둘 다 `updatedAt` 이 더 최신인 쪽이 이긴다.
class AppState extends ChangeNotifier {
  AppState._(this._prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const _storageKey = 'brainmemorizer.data.v1';

  final SharedPreferences _prefs;
  final DateTime Function() _clock;
  final List<StudyCategory> categories = [];
  final List<StudyCard> cards = [];
  final _changes = StreamController<StateChange>.broadcast();

  /// 사용자 망각곡선 배율. 1.0 = 평균.
  double memoryFactor = 1.0;
  DateTime memoryFactorUpdatedAt = epoch;

  Stream<StateChange> get changes => _changes.stream;

  static Future<AppState> load({DateTime Function()? clock}) async {
    final state = AppState._(
      await SharedPreferences.getInstance(),
      clock: clock,
    );
    final raw = state._prefs.getString(_storageKey);
    if (raw != null) {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      state.memoryFactor = (json['memoryFactor'] as num).toDouble();
      final factorTime = json['memoryFactorUpdatedAt'];
      if (factorTime is int) {
        state.memoryFactorUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
          factorTime,
        );
      }
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

  /// 시각 + 무작위 값. 여러 기기가 같은 순간에 만들어도 겹치지 않아야
  /// 동기화할 때 서로 다른 데이터가 같은 것으로 합쳐지지 않는다.
  String _newId() =>
      '${_clock().microsecondsSinceEpoch}-'
      '${_random.nextInt(1 << 32).toRadixString(16)}';

  final _random = math.Random.secure();

  StudyCategory? categoryById(String? id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  StudyCard? cardById(String id) {
    for (final c in cards) {
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

  // ---- 이 기기에서의 변경 --------------------------------------------------

  StudyCategory addCategory(String name) {
    final category = StudyCategory(
      id: _newId(),
      name: name,
      updatedAt: _clock(),
    );
    categories.add(category);
    _saveAndNotify([CategoryUpserted(category)]);
    return category;
  }

  void deleteCategory(String id) {
    final cardIds = cardsIn(id).map((c) => c.id).toList();
    categories.removeWhere((c) => c.id == id);
    cards.removeWhere((c) => c.categoryId == id);
    _saveAndNotify([CategoryDeleted(id, cardIds)]);
  }

  void addCard(
    String categoryId,
    String question,
    String answer, {
    int grade = 1,
  }) {
    final card = _newCard(categoryId, question, answer, grade);
    cards.add(card);
    _saveAndNotify([CardUpserted(card)]);
  }

  /// 여러 카드를 한 번에 넣는다. 같은 질문이 이미 있으면 건너뛰고,
  /// 실제로 추가한 개수를 돌려준다.
  int addCards(String categoryId, Iterable<CollectedCard> collected) {
    final existing = cardsIn(categoryId).map((c) => c.question).toSet();
    final added = <StudyCard>[];
    for (final c in collected) {
      if (!existing.add(c.question)) continue;
      final card = _newCard(categoryId, c.question, c.answer, c.grade);
      cards.add(card);
      added.add(card);
    }
    if (added.isNotEmpty) _saveAndNotify(added.map(CardUpserted.new).toList());
    return added.length;
  }

  StudyCard _newCard(
    String categoryId,
    String question,
    String answer,
    int grade,
  ) {
    final now = _clock();
    return StudyCard(
      id: _newId(),
      categoryId: categoryId,
      question: question,
      answer: answer,
      grade: grade.clamp(1, subcategoryCount),
      dueAt: now,
      updatedAt: now,
    );
  }

  void deleteCard(String id) {
    cards.removeWhere((c) => c.id == id);
    _saveAndNotify([CardDeleted(id)]);
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
    now ??= _clock();
    final last = card.lastReviewedAt;
    final isRealReview = last != null && !failedThisSession;
    final changes = <StateChange>[];

    if (isRealReview) {
      final elapsedDays =
          now.difference(last).inSeconds / Duration.secondsPerDay;
      memoryFactor = MemoryModel.adjustFactor(
        memoryFactor,
        elapsedDays: elapsedDays,
        stability: card.stability,
        recalled: correct,
      );
      memoryFactorUpdatedAt = now;
      changes.add(ProfileChanged(memoryFactor, now));
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
    card.updatedAt = now;
    changes.add(CardUpserted(card));
    _saveAndNotify(changes);
  }

  /// 지금 상태 전체를 변경 목록으로 만든다. 원격 저장소에 처음 밀어 넣을 때 쓴다.
  List<StateChange> snapshotChanges() => [
    for (final c in categories) CategoryUpserted(c),
    for (final c in cards) CardUpserted(c),
    if (memoryFactorUpdatedAt != epoch)
      ProfileChanged(memoryFactor, memoryFactorUpdatedAt),
  ];

  // ---- 다른 기기에서 온 변경 ----------------------------------------------
  // 이쪽은 [changes] 로 다시 내보내지 않는다 (원격에서 왔으니 되돌려 보낼 이유가 없다).

  /// 원격 사본이 더 새로우면 받아들인다. 받아들였으면 true.
  bool applyRemoteCategory(StudyCategory remote) {
    final local = categoryById(remote.id);
    if (local == null) {
      categories.add(remote);
    } else if (remote.updatedAt.isAfter(local.updatedAt)) {
      local
        ..name = remote.name
        ..updatedAt = remote.updatedAt;
    } else {
      return false;
    }
    _saveAndNotify(const []);
    return true;
  }

  bool applyRemoteCategoryDeleted(String id) {
    if (categoryById(id) == null) return false;
    categories.removeWhere((c) => c.id == id);
    cards.removeWhere((c) => c.categoryId == id);
    _saveAndNotify(const []);
    return true;
  }

  bool applyRemoteCard(StudyCard remote) {
    final local = cardById(remote.id);
    if (local == null) {
      cards.add(remote);
    } else if (remote.updatedAt.isAfter(local.updatedAt)) {
      local.copyFrom(remote);
    } else {
      return false;
    }
    _saveAndNotify(const []);
    return true;
  }

  bool applyRemoteCardDeleted(String id) {
    if (cardById(id) == null) return false;
    cards.removeWhere((c) => c.id == id);
    _saveAndNotify(const []);
    return true;
  }

  bool applyRemoteProfile(double factor, DateTime updatedAt) {
    if (!updatedAt.isAfter(memoryFactorUpdatedAt)) return false;
    memoryFactor = factor;
    memoryFactorUpdatedAt = updatedAt;
    _saveAndNotify(const []);
    return true;
  }

  void _saveAndNotify(List<StateChange> changes) {
    _prefs.setString(
      _storageKey,
      jsonEncode({
        'memoryFactor': memoryFactor,
        'memoryFactorUpdatedAt': memoryFactorUpdatedAt.millisecondsSinceEpoch,
        'categories': categories.map((c) => c.toJson()).toList(),
        'cards': cards.map((c) => c.toJson()).toList(),
      }),
    );
    notifyListeners();
    changes.forEach(_changes.add);
  }

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }
}
