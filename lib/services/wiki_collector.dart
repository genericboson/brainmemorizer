import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// 자동 수집으로 만든 카드 한 장.
class CollectedCard {
  const CollectedCard({
    required this.question,
    required this.answer,
    required this.grade,
  });

  final String question;
  final String answer;

  /// 1(가장 중요) ~ [subcategoryCount](가장 덜 중요).
  final int grade;
}

/// 자동 수집 결과: 실제로 사용한 위키백과 문서 제목과 카드들.
class CollectResult {
  const CollectResult({required this.title, required this.cards});

  final String title;
  final List<CollectedCard> cards;
}

class CollectException implements Exception {
  CollectException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 한국어 위키백과에서 주제 문서를 가져와 빈칸 채우기 카드를 만든다.
///
/// 문서 본문에서 다른 문서로 링크된 용어를 정답 후보로 삼는다. 용어가
/// 본문에 자주 나오고 문서 앞부분(개요)에 등장할수록 중요하다고 보고,
/// 중요도 순위를 10등분해 등급을 매긴다.
class WikiCollector {
  WikiCollector({http.Client? client}) : _client = client ?? http.Client();

  static const _endpoint = 'https://ko.wikipedia.org/w/api.php';
  static const _userAgent = 'brainmemorizer/1.0 (flutter study app)';

  static const _minSentenceLength = 15;
  static const _maxSentenceLength = 160;
  static const _minTermLength = 2;
  static const _maxTermLength = 25;

  final http.Client _client;

  Future<CollectResult> collect(String topic, {int maxCards = 100}) async {
    final title = await _searchTitle(topic);
    if (title == null) {
      throw CollectException("'$topic' 문서를 위키백과에서 찾지 못했습니다.");
    }
    final html = await _fetchHtml(title);
    final cards = extractCards(html, title: title, maxCards: maxCards);
    if (cards.isEmpty) {
      throw CollectException("'$title' 문서에서 만들 수 있는 문제가 없습니다.");
    }
    return CollectResult(title: title, cards: cards);
  }

  Future<Map<String, dynamic>> _get(Map<String, String> params) async {
    final uri = Uri.parse(_endpoint).replace(
      queryParameters: {...params, 'format': 'json', 'formatversion': '2'},
    );
    final http.Response response;
    try {
      response = await _client.get(uri, headers: {'User-Agent': _userAgent});
    } catch (e) {
      throw CollectException('위키백과에 연결하지 못했습니다: $e');
    }
    if (response.statusCode != 200) {
      throw CollectException('위키백과 응답 오류 (HTTP ${response.statusCode})');
    }
    // 응답 헤더의 charset 과 무관하게 항상 UTF-8 로 읽는다.
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  Future<String?> _searchTitle(String topic) async {
    final json = await _get({
      'action': 'query',
      'list': 'search',
      'srsearch': topic,
      'srlimit': '1',
    });
    final results = (json['query']?['search'] as List?) ?? const [];
    if (results.isEmpty) return null;
    return (results.first as Map<String, dynamic>)['title'] as String;
  }

  Future<String> _fetchHtml(String title) async {
    final json = await _get({
      'action': 'parse',
      'page': title,
      'prop': 'text',
      'disabletoc': '1',
      'disableeditsection': '1',
    });
    final text = json['parse']?['text'];
    if (text is! String) {
      throw CollectException("'$title' 문서 본문을 읽지 못했습니다.");
    }
    return text;
  }

  /// 문서 HTML 에서 카드를 뽑아낸다. 네트워크 없이 테스트할 수 있도록 분리했다.
  static List<CollectedCard> extractCards(
    String html, {
    required String title,
    int maxCards = 100,
  }) {
    final paragraphs = RegExp(
      r'<p[^>]*>(.*?)</p>',
      dotAll: true,
    ).allMatches(html).map((m) => m.group(1)!).toList();

    final stats = <String, _TermStats>{};
    for (var i = 0; i < paragraphs.length; i++) {
      final raw = paragraphs[i];
      final terms = _linkTexts(raw);
      if (terms.isEmpty) continue;
      final sentences = _sentences(_plainText(raw));
      for (final term in terms) {
        if (!_isUsableTerm(term, title)) continue;
        final stat = stats.putIfAbsent(term, () => _TermStats(i));
        stat.mentions++;
        if (stat.sentence != null) continue;
        for (final s in sentences) {
          if (_isUsableSentence(s, term)) {
            stat.sentence = s;
            break;
          }
        }
      }
    }

    final ranked = stats.entries.where((e) => e.value.sentence != null).toList()
      ..sort((a, b) => b.value.score.compareTo(a.value.score));
    final picked = ranked.take(maxCards).toList();

    return [
      for (var rank = 0; rank < picked.length; rank++)
        CollectedCard(
          question:
              '빈칸에 들어갈 말은? '
              '${picked[rank].value.sentence!.replaceAll(picked[rank].key, '____')}',
          answer: picked[rank].key,
          grade: 1 + (rank * subcategoryCount) ~/ picked.length,
        ),
    ];
  }

  static final _linkPattern = RegExp(
    r'<a\s+[^>]*href="/wiki/(?![^"]*:)[^"]*"[^>]*>(.*?)</a>',
    dotAll: true,
  );
  static final _tagPattern = RegExp(r'<[^>]+>');
  static final _supPattern = RegExp(r'<sup.*?</sup>', dotAll: true);
  static final _parenPattern = RegExp(r'\([^()]*\)');
  static final _sentenceEnd = RegExp(r'(?<=[.!?])\s+');

  /// 숫자와 '1897년', '3세기' 같은 날짜 표현.
  static final _numeric = RegExp(r'^[\d\s.,~\-–]+(년|월|일|세기|년대)?$');

  static List<String> _linkTexts(String raw) => _linkPattern
      .allMatches(raw)
      .map(
        (m) => _decodeEntities(m.group(1)!.replaceAll(_tagPattern, '')).trim(),
      )
      .toList();

  static String _plainText(String raw) => _decodeEntities(
    raw.replaceAll(_supPattern, '').replaceAll(_tagPattern, ''),
  ).replaceAll(_parenPattern, '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static List<String> _sentences(String text) =>
      text.split(_sentenceEnd).map((s) => s.trim()).toList();

  static bool _isUsableTerm(String term, String title) =>
      term.length >= _minTermLength &&
      term.length <= _maxTermLength &&
      term != title &&
      !_numeric.hasMatch(term);

  static bool _isUsableSentence(String sentence, String term) =>
      sentence.length >= _minSentenceLength &&
      sentence.length <= _maxSentenceLength &&
      sentence.contains(term) &&
      // 용어가 문장의 대부분이면 빈칸 문제로서 의미가 없다.
      sentence.length - term.length >= _minSentenceLength;

  static String _decodeEntities(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}

class _TermStats {
  _TermStats(this.firstParagraph);

  final int firstParagraph;
  int mentions = 0;
  String? sentence;

  /// 자주 언급될수록, 문서 앞쪽에 나올수록 높다.
  double get score => mentions + 5.0 / (1 + firstParagraph);
}
