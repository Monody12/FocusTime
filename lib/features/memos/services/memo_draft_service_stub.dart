import 'package:shared_preferences/shared_preferences.dart';

String _key(String memoId) => 'focus_my_time.memo_draft.$memoId';

Future<String?> readMemoDraft(String memoId) async {
  final preferences = await SharedPreferences.getInstance();
  return preferences.getString(_key(memoId));
}

Future<void> writeMemoDraft(String memoId, String value) async {
  final preferences = await SharedPreferences.getInstance();
  final saved = await preferences.setString(_key(memoId), value);
  if (!saved) throw StateError('草稿写入失败');
}

Future<void> clearMemoDraft(String memoId) async {
  final preferences = await SharedPreferences.getInstance();
  final removed = await preferences.remove(_key(memoId));
  if (!removed && preferences.containsKey(_key(memoId))) {
    throw StateError('草稿清理失败');
  }
}
