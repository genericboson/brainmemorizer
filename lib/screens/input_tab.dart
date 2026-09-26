import 'package:flutter/material.dart';

import '../app_state.dart';
import '../services/wiki_collector.dart';
import '../widgets/category_picker.dart';
import '../widgets/subcategory_picker.dart';

/// '학습데이터 주입' 탭: 카테고리를 만들고 그 안에 질문/정답을 넣는다.
class InputTab extends StatefulWidget {
  const InputTab({super.key, required this.state, this.collector});

  final AppState state;

  /// 자동 수집기. 테스트에서 가짜로 바꿔 끼울 수 있다.
  final WikiCollector? collector;

  @override
  State<InputTab> createState() => _InputTabState();
}

class _InputTabState extends State<InputTab> {
  String? _categoryId;
  int _subcategory = 1;
  bool _collecting = false;
  final _questionController = TextEditingController();
  final _answerController = TextEditingController();
  final _questionFocus = FocusNode();

  AppState get state => widget.state;

  @override
  void dispose() {
    _questionController.dispose();
    _answerController.dispose();
    _questionFocus.dispose();
    super.dispose();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addCategory() async {
    final name = await _promptText(context, '새 카테고리', '카테고리 이름');
    if (name == null) return;
    final category = state.addCategory(name);
    setState(() => _categoryId = category.id);
  }

  Future<void> _deleteCategory(String id) async {
    final category = state.categoryById(id)!;
    final count = state.cardsIn(id).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('카테고리 삭제'),
        content: Text("'${category.name}'와 학습데이터 $count개를 삭제할까요?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    state.deleteCategory(id);
    setState(() => _categoryId = null);
  }

  void _addCard(String categoryId) {
    final question = _questionController.text.trim();
    final answer = _answerController.text.trim();
    if (question.isEmpty || answer.isEmpty) {
      _showMessage('질문과 정답을 모두 입력하세요.');
      return;
    }
    state.addCard(categoryId, question, answer, grade: _subcategory);
    _questionController.clear();
    _answerController.clear();
    _questionFocus.requestFocus();
  }

  Future<void> _collect(String categoryId) async {
    final topic = state.categoryById(categoryId)!.name;
    setState(() => _collecting = true);
    try {
      final collector = widget.collector ?? WikiCollector();
      final result = await collector.collect(topic);
      final added = state.addCards(categoryId, result.cards);
      final source = result.title == topic
          ? ''
          : " (위키백과 '${result.title}' 문서)";
      _showMessage(
        added == 0
            ? "'$topic'$source에서 새로 추가할 학습데이터가 없습니다."
            : "'$topic'$source 학습데이터 $added개를 추가했습니다.",
      );
    } on CollectException catch (e) {
      _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _collecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final categoryId =
            state.categoryById(_categoryId)?.id ??
            (state.categories.isEmpty ? null : state.categories.first.id);
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
                      onChanged: (n) => setState(() => _subcategory = n ?? 1),
                    ),
                  ),
                  IconButton(
                    tooltip: '카테고리 추가',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: _addCategory,
                  ),
                  if (categoryId != null)
                    IconButton(
                      tooltip: '카테고리 삭제',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _deleteCategory(categoryId),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (categoryId == null)
                const Expanded(
                  child: Center(child: Text('오른쪽 위 폴더 버튼으로 카테고리를 먼저 만드세요.')),
                )
              else ...[
                _CountsRow(
                  state: state,
                  categoryId: categoryId,
                  subcategory: _subcategory,
                ),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _collecting ? null : () => _collect(categoryId),
                  icon: _collecting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.travel_explore),
                  label: Text(_collecting ? '수집 중...' : '학습 데이터 자동 수집'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _questionController,
                  focusNode: _questionFocus,
                  decoration: const InputDecoration(
                    labelText: '질문',
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _answerController,
                  decoration: const InputDecoration(
                    labelText: '정답 (단답형)',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addCard(categoryId),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _addCard(categoryId),
                  icon: const Icon(Icons.add),
                  label: Text('서브카테고리 $_subcategory에 추가'),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _CardList(
                    state: state,
                    categoryId: categoryId,
                    subcategory: _subcategory,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _CountsRow extends StatelessWidget {
  const _CountsRow({
    required this.state,
    required this.categoryId,
    required this.subcategory,
  });

  final AppState state;
  final String categoryId;
  final int subcategory;

  @override
  Widget build(BuildContext context) {
    final total = state.cardsIn(categoryId).length;
    final inSub = state.cardsIn(categoryId, subcategory: subcategory).length;
    final name = state.categoryById(categoryId)!.name;
    return Text(
      "'$name' 전체 $total개 · 서브카테고리 $subcategory: $inSub개",
      style: Theme.of(context).textTheme.titleSmall,
    );
  }
}

class _CardList extends StatelessWidget {
  const _CardList({
    required this.state,
    required this.categoryId,
    required this.subcategory,
  });

  final AppState state;
  final String categoryId;
  final int subcategory;

  @override
  Widget build(BuildContext context) {
    final cards = state
        .cardsIn(categoryId, subcategory: subcategory)
        .reversed
        .toList();
    if (cards.isEmpty) {
      return const Center(child: Text('이 서브카테고리에는 아직 학습데이터가 없습니다.'));
    }
    return ListView.separated(
      itemCount: cards.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final card = cards[i];
        return ListTile(
          leading: CircleAvatar(
            radius: 14,
            child: Text('${card.grade}', style: const TextStyle(fontSize: 12)),
          ),
          title: Text(card.question),
          subtitle: Text('정답: ${card.answer}'),
          trailing: IconButton(
            tooltip: '삭제',
            icon: const Icon(Icons.close),
            onPressed: () => state.deleteCard(card.id),
          ),
        );
      },
    );
  }
}

Future<String?> _promptText(
  BuildContext context,
  String title,
  String label,
) async {
  final result = await showDialog<String>(
    context: context,
    builder: (context) => _TextPromptDialog(title: title, label: label),
  );
  return (result == null || result.isEmpty) ? null : result;
}

/// 텍스트 한 줄을 입력받는 대화상자. 컨트롤러를 대화상자와 함께 정리한다.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({required this.title, required this.label});

  final String title;
  final String label;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: widget.label),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(onPressed: _submit, child: const Text('만들기')),
      ],
    );
  }
}
