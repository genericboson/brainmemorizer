import 'memory_model.dart';

/// 저장된 데이터에 갱신 시각이 없을 때 쓰는 값. 어떤 원격 사본보다도 오래됐다고 본다.
final DateTime epoch = DateTime.fromMillisecondsSinceEpoch(0);

DateTime _readTime(Map<String, dynamic> json, String key) {
  final v = json[key];
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is String) return DateTime.parse(v);
  return epoch;
}

class StudyCategory {
  StudyCategory({required this.id, required this.name, DateTime? updatedAt})
    : updatedAt = updatedAt ?? epoch;

  final String id;
  String name;

  /// 마지막으로 바뀐 시각. 기기 간 동기화에서 최신 사본을 고르는 기준.
  DateTime updatedAt;

  factory StudyCategory.fromJson(Map<String, dynamic> json) => StudyCategory(
    id: json['id'] as String,
    name: json['name'] as String,
    updatedAt: _readTime(json, 'updatedAt'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };
}

/// 서브카테고리 개수. 서브카테고리 N 에는 중요도 등급이 N 이하인 카드가 들어간다.
const int subcategoryCount = 10;

/// 질문 하나와 그 정답, 그리고 망각곡선 상의 상태.
class StudyCard {
  StudyCard({
    required this.id,
    required this.categoryId,
    required this.question,
    required this.answer,
    required this.dueAt,
    this.grade = 1,
    this.stability = MemoryModel.initialStability,
    this.reviewCount = 0,
    this.lapseCount = 0,
    this.lastReviewedAt,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? epoch;

  final String id;
  final String categoryId;
  final String question;
  final String answer;

  /// 중요도 등급. 1 이 가장 중요하고 [subcategoryCount] 가 가장 덜 중요하다.
  final int grade;
  double stability;
  int reviewCount;
  int lapseCount;
  DateTime? lastReviewedAt;
  DateTime dueAt;

  /// 마지막으로 바뀐 시각. 기기 간 동기화에서 최신 사본을 고르는 기준.
  DateTime updatedAt;

  bool get isNew => lastReviewedAt == null;

  bool isDue(DateTime now) => !dueAt.isAfter(now);

  factory StudyCard.fromJson(Map<String, dynamic> json) => StudyCard(
    id: json['id'] as String,
    categoryId: json['categoryId'] as String,
    question: json['question'] as String,
    answer: json['answer'] as String,
    grade: json['grade'] as int? ?? 1,
    stability: (json['stability'] as num).toDouble(),
    reviewCount: json['reviewCount'] as int,
    lapseCount: json['lapseCount'] as int,
    lastReviewedAt: json['lastReviewedAt'] == null
        ? null
        : DateTime.parse(json['lastReviewedAt'] as String),
    dueAt: DateTime.parse(json['dueAt'] as String),
    updatedAt: _readTime(json, 'updatedAt'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'categoryId': categoryId,
    'question': question,
    'answer': answer,
    'grade': grade,
    'stability': stability,
    'reviewCount': reviewCount,
    'lapseCount': lapseCount,
    'lastReviewedAt': lastReviewedAt?.toIso8601String(),
    'dueAt': dueAt.toIso8601String(),
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  /// 다른 사본의 내용을 이 카드에 덮어쓴다 (id, categoryId, question, answer 는 같다고 본다).
  void copyFrom(StudyCard other) {
    stability = other.stability;
    reviewCount = other.reviewCount;
    lapseCount = other.lapseCount;
    lastReviewedAt = other.lastReviewedAt;
    dueAt = other.dueAt;
    updatedAt = other.updatedAt;
  }
}

/// 단답형 채점: 대소문자와 공백 차이는 무시한다.
bool isCorrectAnswer(String input, String answer) {
  String normalize(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
  return normalize(input) == normalize(answer);
}
