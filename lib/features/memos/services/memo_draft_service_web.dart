import 'package:web/web.dart' as web;

String _key(String memoId) => 'focus_my_time.memo_draft.$memoId';

Future<String?> readMemoDraft(String memoId) async =>
    web.window.localStorage.getItem(_key(memoId));

Future<void> writeMemoDraft(String memoId, String value) async =>
    web.window.localStorage.setItem(_key(memoId), value);

Future<void> clearMemoDraft(String memoId) async =>
    web.window.localStorage.removeItem(_key(memoId));
