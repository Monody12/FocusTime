import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/features/memos/services/memo_draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('原生恢复草稿支持写入、读取和清理', () async {
    const memoId = 'draft-test';
    const payload = '{"title":"未保存标题","body":"未保存正文"}';

    await writeMemoDraft(memoId, payload);
    expect(await readMemoDraft(memoId), payload);

    await clearMemoDraft(memoId);
    expect(await readMemoDraft(memoId), isNull);
  });
}
