import 'package:web/web.dart' as web;

String _key(String memoId) => 'focus_my_time.memo_draft.$memoId';

String? readMemoDraft(String memoId) =>
    web.window.localStorage.getItem(_key(memoId));

void writeMemoDraft(String memoId, String value) =>
    web.window.localStorage.setItem(_key(memoId), value);

void clearMemoDraft(String memoId) =>
    web.window.localStorage.removeItem(_key(memoId));
