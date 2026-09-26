import 'dart:math' as math;

/// 에빙하우스 망각곡선 R(t) = exp(-t / (S * m)) 을 쓰는 기억 모델.
///
/// - S (stability): 카드별 기억 안정도(일). 평균적인 사람 기준 값이다.
/// - m (memory factor): 사용자별 배율. 1.0 이 평균 망각곡선이고,
///   복습 결과를 볼 때마다 조금씩 조정된다. 잘 잊는 사람은 1보다 작아져
///   복습 간격이 짧아지고, 잘 기억하는 사람은 커져 간격이 길어진다.
class MemoryModel {
  MemoryModel._();

  /// 처음 외운 카드의 안정도. 하루 뒤 약 37%를 기억하는 평균 곡선.
  static const double initialStability = 1.0;

  /// 제때 복습에 성공할 때마다 안정도가 늘어나는 배수.
  static const double stabilityGrowth = 2.5;

  /// 복습에 실패했을 때 안정도에 곱하는 값.
  static const double lapseFactor = 0.5;

  static const double minStability = 0.2;

  /// 기억 확률이 이 값까지 떨어지는 시점에 복습을 잡는다.
  static const double targetRetention = 0.8;

  /// 사용자 배율 조정 속도. 작을수록 서서히 바뀐다.
  static const double learningRate = 0.1;

  /// 한 번의 복습으로 배율이 바뀔 수 있는 최대 폭(로그 스케일).
  static const double maxStep = 0.2;

  static const double minFactor = 0.2;
  static const double maxFactor = 5.0;

  /// 마지막 복습 후 [elapsedDays] 가 지났을 때 기억하고 있을 확률.
  static double recallProbability(
    double elapsedDays,
    double stability,
    double factor,
  ) {
    return math.exp(-elapsedDays / (stability * factor));
  }

  /// 기억 확률이 [targetRetention] 으로 떨어질 때까지의 시간.
  static Duration reviewInterval(double stability, double factor) {
    final days = stability * factor * math.log(1 / targetRetention);
    return Duration(seconds: (days * Duration.secondsPerDay).round());
  }

  /// 한 번의 복습 결과로 사용자 배율을 조정한다.
  ///
  /// 모델이 예측한 기억 확률과 실제 결과의 차이(로그 손실의 기울기)만큼
  /// 배율을 움직인다. 결과적으로 사용자의 실제 정답률이 [targetRetention]
  /// 에 가까워질 때까지 복습 간격이 늘거나 줄어든다.
  static double adjustFactor(
    double factor, {
    required double elapsedDays,
    required double stability,
    required bool recalled,
  }) {
    final x = elapsedDays / (stability * factor);
    final p = math.exp(-x).clamp(0.01, 0.99);
    final step = recalled ? learningRate * x : -learningRate * x * p / (1 - p);
    final next = factor * math.exp(step.clamp(-maxStep, maxStep));
    return next.clamp(minFactor, maxFactor);
  }
}
