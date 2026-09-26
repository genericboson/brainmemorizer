import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets/category_picker.dart';
import '../widgets/subcategory_picker.dart';

/// '학습' 탭: 고른 카테고리와 서브카테고리의 카드로 단답형 퀴즈를 푼다.
class StudyTab extends StatefulWidget {
  const StudyTab({super.key, required this.state});

  final AppState state;

  @override
  State<StudyTab> createState() => _StudyTabState();
}

class _StudyTabState extends State<StudyTab> {
  String? _categoryId;
  int _subcategory = subcategoryCount;
  _Session? _session;

  AppState get state => widget.state;

  void _start(String categoryId, {required bool practice}) {
    final cards = practice
        ? state.cardsIn(categoryId, subcategory: _subcategory)
        : state.dueCardsIn(
            categoryId,
            DateTime.now(),
            subcategory: _subcategory,
          );
    setState(() {
      _session = _Session(queue: cards..shuffle(), practice: practice);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return _QuizView(
        state: state,
        session: session,
        onExit: () => setState(() => _session = null),
      );
    }
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => _buildSetup(context),
    );
  }

  Widget _buildSetup(BuildContext context) {
    final categoryId =
        state.categoryById(_categoryId)?.id ??
        (state.categories.isEmpty ? null : state.categories.first.id);
    final now = DateTime.now();
    final inCategory = categoryId == null
        ? <StudyCard>[]
        : state.cardsIn(categoryId);
    final all = categoryId == null
        ? <StudyCard>[]
        : state.cardsIn(categoryId, subcategory: _subcategory);
    final due = categoryId == null
        ? <StudyCard>[]
        : state.dueCardsIn(categoryId, now, subcategory: _subcategory);
    final upcoming = all.where((c) => !c.isDue(now)).toList()
      ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: CategoryPicker(
                  state: state,
                  selectedId: categoryId,
                  onChanged: (id) => setState(() => _categoryId = id),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SubcategoryPicker(
                  value: _subcategory,
                  onChanged: (n) =>
                      setState(() => _subcategory = n ?? subcategoryCount),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (categoryId == null)
            const Text("'학습데이터 주입' 탭에서 카테고리와 학습데이터를 먼저 만드세요.")
          else if (inCategory.isEmpty)
            const Text('이 카테고리에는 아직 학습데이터가 없습니다.')
          else ...[
            _ProgressBar(
              label: "'${state.categoryById(categoryId)!.name}' 전체",
              learned: AppState.learnedCount(inCategory, now),
              total: inCategory.length,
            ),
            const SizedBox(height: 8),
            _ProgressBar(
              label: '서브카테고리 $_subcategory',
              learned: AppState.learnedCount(all, now),
              total: all.length,
            ),
            const SizedBox(height: 16),
            Text('지금 복습할 문제 ${due.length}개', style: textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '서브카테고리 $_subcategory 전체 ${all.length}개'
              '${upcoming.isEmpty ? '' : ' · 다음 복습 ${_formatUntil(upcoming.first.dueAt, now)}'}',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: due.isEmpty
                  ? null
                  : () => _start(categoryId, practice: false),
              child: const Text('학습 시작'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _start(categoryId, practice: true),
              child: const Text('미리 학습 (전체 문제, 기록에 반영 안 함)'),
            ),
          ],
          const Spacer(),
          _MemoryFactorCard(factor: state.memoryFactor),
        ],
      ),
    );
  }
}

/// 학습 진행도: 한 번 이상 맞혀서 아직 복습 시점이 오지 않은 카드의 비율.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.label,
    required this.learned,
    required this.total,
  });

  final String label;
  final int learned;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : learned / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: 학습 완료 $learned/$total (${(ratio * 100).round()}%)'),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: ratio, minHeight: 8),
      ],
    );
  }
}

class _MemoryFactorCard extends StatelessWidget {
  const _MemoryFactorCard({required this.factor});

  final double factor;

  @override
  Widget build(BuildContext context) {
    final percent = (factor * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '내 기억 유지력: 평균의 $percent%',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            const Text(
              '평균 망각곡선에서 시작해, 복습 결과에 맞춰 조금씩 조정됩니다. '
              '자주 틀리면 복습 간격이 짧아지고, 잘 맞히면 길어집니다.',
            ),
          ],
        ),
      ),
    );
  }
}

class _Session {
  _Session({required this.queue, required this.practice});

  final List<StudyCard> queue;
  final bool practice;
  final Set<String> failedIds = {};
  int answered = 0;
  int correctFirstTry = 0;
  int total = 0;

  StudyCard? get current => queue.isEmpty ? null : queue.first;
}

class _QuizView extends StatefulWidget {
  const _QuizView({
    required this.state,
    required this.session,
    required this.onExit,
  });

  final AppState state;
  final _Session session;
  final VoidCallback onExit;

  @override
  State<_QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<_QuizView> {
  final _controller = TextEditingController();
  final _inputFocus = FocusNode();
  final _nextFocus = FocusNode();

  /// 채점 결과. null 이면 아직 답을 내지 않은 상태.
  bool? _correct;

  _Session get session => widget.session;

  @override
  void initState() {
    super.initState();
    session.total = session.queue.length;
  }

  @override
  void dispose() {
    _controller.dispose();
    _inputFocus.dispose();
    _nextFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final card = session.current;
    if (card == null || _correct != null) return;
    if (_controller.text.trim().isEmpty) return;
    setState(() => _correct = isCorrectAnswer(_controller.text, card.answer));
    _nextFocus.requestFocus();
  }

  /// 채점 결과를 확정하고 다음 문제로 넘어간다.
  void _next({required bool correct}) {
    final card = session.current!;
    final failedBefore = session.failedIds.contains(card.id);
    if (!session.practice) {
      widget.state.recordAnswer(
        card,
        correct: correct,
        failedThisSession: failedBefore,
      );
    }
    session.queue.removeAt(0);
    if (correct) {
      session.answered++;
      if (!failedBefore) session.correctFirstTry++;
    } else {
      // 틀린 문제는 맞힐 때까지 이번 학습 끝에 다시 나온다.
      session.failedIds.add(card.id);
      session.queue.add(card);
    }
    setState(() {
      _correct = null;
      _controller.clear();
    });
    _inputFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final card = session.current;
    final textTheme = Theme.of(context).textTheme;

    if (card == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('학습 완료!', style: textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('${session.total}문제 중 한 번에 맞힌 문제 ${session.correctFirstTry}개'),
            const SizedBox(height: 16),
            FilledButton(onPressed: widget.onExit, child: const Text('돌아가기')),
          ],
        ),
      );
    }

    final correct = _correct;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${session.practice ? '미리 학습' : '학습'} · '
                  '맞힌 문제 ${session.answered}/${session.total}',
                ),
              ),
              TextButton(onPressed: widget.onExit, child: const Text('그만하기')),
            ],
          ),
          const SizedBox(height: 24),
          Text(card.question, style: textTheme.headlineSmall),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            focusNode: _inputFocus,
            autofocus: true,
            readOnly: correct != null,
            decoration: const InputDecoration(
              labelText: '정답 입력',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          if (correct == null)
            FilledButton(onPressed: _submit, child: const Text('확인'))
          else ...[
            Text(
              correct ? '정답입니다!' : '틀렸습니다. 정답: ${card.answer}',
              style: textTheme.titleMedium?.copyWith(
                color: correct ? Colors.green.shade700 : Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              focusNode: _nextFocus,
              onPressed: () => _next(correct: correct),
              child: const Text('다음'),
            ),
            if (!correct) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _next(correct: true),
                child: const Text('맞은 걸로 처리 (오타 등)'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

String _formatUntil(DateTime due, DateTime now) {
  final diff = due.difference(now);
  if (diff.inMinutes < 1) return '곧';
  if (diff.inHours < 1) return '${diff.inMinutes}분 후';
  if (diff.inDays < 1) return '${diff.inHours}시간 후';
  return '${diff.inDays}일 후';
}
