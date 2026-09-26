import 'package:flutter/material.dart';

import '../models.dart';

/// 서브카테고리(1~10) 선택 드롭다운. 숫자가 작을수록 중요한 데이터만 담긴다.
class SubcategoryPicker extends StatelessWidget {
  const SubcategoryPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      key: ValueKey(value),
      initialValue: value,
      decoration: const InputDecoration(
        labelText: '서브카테고리',
        border: OutlineInputBorder(),
      ),
      items: [
        for (var n = 1; n <= subcategoryCount; n++)
          DropdownMenuItem(value: n, child: Text('$n')),
      ],
      onChanged: onChanged,
    );
  }
}
