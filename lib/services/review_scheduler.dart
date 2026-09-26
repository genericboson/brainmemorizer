import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_state.dart';
import '../models.dart';

/// 망각곡선에 따라 복습 시점이 된 카드를 감시하고, 새로 복습할 카드가
/// 생기면 [onDue] 를 부른다.
///
/// 한 번 알린 카드는 복습을 마쳐 다음 복습 시점이 미래로 옮겨지기 전까지
/// 다시 알리지 않는다. 그래서 알림은 "새로 복습할 것이 생겼을 때"만 뜬다.
class ReviewScheduler {
  ReviewScheduler(
    this.state, {
    required this.onDue,
    this.interval = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppState state;

  /// 새로 복습할 카드가 생겼을 때. 인자는 지금 복습할 전체 카드 수.
  final ValueChanged<int> onDue;
  final Duration interval;
  final DateTime Function() _clock;

  final Set<String> _announced = {};
  Timer? _timer;

  /// 지금 복습할 전체 카드 수. 마지막 [check] 기준이다.
  int dueCount = 0;

  void start() {
    state.addListener(_onStateChanged);
    _timer = Timer.periodic(interval, (_) => check());
    check();
  }

  void dispose() {
    _timer?.cancel();
    state.removeListener(_onStateChanged);
  }

  void _onStateChanged() => check();

  /// 복습할 카드를 다시 세고, 아직 알리지 않은 카드가 있으면 [onDue] 를 부른다.
  /// 새로 알린 카드 수를 돌려준다.
  int check() {
    final now = _clock();
    final due = state.cards.where((c) => c.isDue(now)).toList();
    dueCount = due.length;

    // 복습을 마쳐 더 이상 due 가 아닌 카드는 다음에 다시 알릴 수 있게 한다.
    final dueIds = due.map((c) => c.id).toSet();
    _announced.retainWhere(dueIds.contains);

    final fresh = due.where((c) => _announced.add(c.id)).length;
    if (fresh > 0) onDue(dueCount);
    return fresh;
  }

  /// 아직 복습 시점이 오지 않은 카드 중 가장 빠른 복습 시각.
  DateTime? nextDueAt() {
    final now = _clock();
    DateTime? next;
    for (final StudyCard c in state.cards) {
      if (c.isDue(now)) continue;
      if (next == null || c.dueAt.isBefore(next)) next = c.dueAt;
    }
    return next;
  }
}
