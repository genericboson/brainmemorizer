import 'package:flutter/material.dart';

import '../app_state.dart';

/// 두 탭이 함께 쓰는 카테고리 선택 드롭다운.
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.state,
    required this.selectedId,
    required this.onChanged,
  });

  final AppState state;
  final String? selectedId;
  final ValueChanged<String?>? onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      // 선택이 바뀌면 새 초기값으로 다시 그리도록 키를 준다.
      key: ValueKey(selectedId),
      initialValue: selectedId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: '카테고리',
        border: OutlineInputBorder(),
      ),
      hint: const Text('카테고리 없음'),
      items: [
        for (final c in state.categories)
          DropdownMenuItem(value: c.id, child: Text(c.name)),
      ],
      onChanged: onChanged,
    );
  }
}
