import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/features/memos/services/memo_diff.dart';

void main() {
  test('逐行差异保留公共行并标记增删内容', () {
    final diff = buildMemoLineDiff('标题\n旧内容\n结尾', '标题\n新内容\n结尾');

    expect(diff.map((line) => line.kind), [
      MemoDiffKind.unchanged,
      MemoDiffKind.removed,
      MemoDiffKind.added,
      MemoDiffKind.unchanged,
    ]);
    expect(diff.map((line) => line.text), ['标题', '旧内容', '新内容', '结尾']);
  });

  test('超大正文使用有界降级策略', () {
    final before = List.generate(601, (index) => '旧$index').join('\n');
    final after = List.generate(601, (index) => '新$index').join('\n');
    final diff = buildMemoLineDiff(before, after);

    expect(diff, hasLength(1202));
    expect(
      diff.take(601).every((line) => line.kind == MemoDiffKind.removed),
      isTrue,
    );
    expect(
      diff.skip(601).every((line) => line.kind == MemoDiffKind.added),
      isTrue,
    );
  });
}
