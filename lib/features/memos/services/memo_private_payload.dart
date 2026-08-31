class MemoPrivatePayload {
  const MemoPrivatePayload({required this.title, required this.bodyMd});

  final String title;
  final String bodyMd;
}

String encodeMemoPrivatePayload({
  required String title,
  required String bodyMd,
}) => '$title\u0000$bodyMd';

MemoPrivatePayload decodeMemoPrivatePayload(String value) {
  final separator = value.indexOf('\u0000');
  if (separator < 0) {
    return MemoPrivatePayload(title: '', bodyMd: value);
  }
  var title = value.substring(0, separator);
  // v1.7.0-v1.8.2 在分隔符前多写了一个换行，读取时兼容清理。
  if (title.endsWith('\n')) title = title.substring(0, title.length - 1);
  return MemoPrivatePayload(
    title: title,
    bodyMd: value.substring(separator + 1),
  );
}
