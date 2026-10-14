import 'package:flutter_test/flutter_test.dart';
import 'package:focus_my_time/data/sync/mcp_api.dart';

void main() {
  test('McpTokenInfo parses server payload and labels scopes', () {
    final info = McpTokenInfo.fromJson({
      'id': 'abc',
      'name': 'Cursor',
      'tokenPrefix': 'fmcp_abcd',
      'scopes': ['tasks:read', 'sessions:read'],
      'expiresAt': 1700000000000,
      'lastUsedAt': null,
      'createdAt': 1690000000000,
    });
    expect(info.id, 'abc');
    expect(info.canWrite, isFalse);
    expect(info.scopeLabel, '只读');
    expect(info.tokenPrefix, 'fmcp_abcd');

    final writer = McpTokenInfo.fromJson({
      'id': 'w',
      'name': 'writer',
      'scopes': ['tasks:read', 'tasks:write'],
      'createdAt': 1,
    });
    expect(writer.canWrite, isTrue);
    expect(writer.scopeLabel, '读写');
  });
}
