enum MemoDiffKind { unchanged, added, removed }

class MemoDiffLine {
  const MemoDiffLine(this.kind, this.text);

  final MemoDiffKind kind;
  final String text;
}

/// Produces a line-oriented diff suitable for version previews.
///
/// Notes larger than 600 lines fall back to two complete removed/added blocks
/// so an unusually large document cannot allocate an unbounded LCS matrix.
List<MemoDiffLine> buildMemoLineDiff(String before, String after) {
  final oldLines = before.split('\n');
  final newLines = after.split('\n');
  if (oldLines.length > 600 || newLines.length > 600) {
    return [
      for (final line in oldLines) MemoDiffLine(MemoDiffKind.removed, line),
      for (final line in newLines) MemoDiffLine(MemoDiffKind.added, line),
    ];
  }

  final lengths = List.generate(
    oldLines.length + 1,
    (_) => List<int>.filled(newLines.length + 1, 0),
  );
  for (var oldIndex = oldLines.length - 1; oldIndex >= 0; oldIndex--) {
    for (var newIndex = newLines.length - 1; newIndex >= 0; newIndex--) {
      lengths[oldIndex][newIndex] = oldLines[oldIndex] == newLines[newIndex]
          ? lengths[oldIndex + 1][newIndex + 1] + 1
          : lengths[oldIndex + 1][newIndex] >= lengths[oldIndex][newIndex + 1]
          ? lengths[oldIndex + 1][newIndex]
          : lengths[oldIndex][newIndex + 1];
    }
  }

  final result = <MemoDiffLine>[];
  var oldIndex = 0;
  var newIndex = 0;
  while (oldIndex < oldLines.length && newIndex < newLines.length) {
    if (oldLines[oldIndex] == newLines[newIndex]) {
      result.add(MemoDiffLine(MemoDiffKind.unchanged, oldLines[oldIndex]));
      oldIndex++;
      newIndex++;
    } else if (lengths[oldIndex + 1][newIndex] >=
        lengths[oldIndex][newIndex + 1]) {
      result.add(MemoDiffLine(MemoDiffKind.removed, oldLines[oldIndex++]));
    } else {
      result.add(MemoDiffLine(MemoDiffKind.added, newLines[newIndex++]));
    }
  }
  while (oldIndex < oldLines.length) {
    result.add(MemoDiffLine(MemoDiffKind.removed, oldLines[oldIndex++]));
  }
  while (newIndex < newLines.length) {
    result.add(MemoDiffLine(MemoDiffKind.added, newLines[newIndex++]));
  }
  return result;
}
