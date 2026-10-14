import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:focus_my_time/data/sync/sync_service.dart';

class McpUnsupportedException implements Exception {
  @override
  String toString() => '当前同步服务器不支持 MCP';
}

class McpApiException implements Exception {
  final String message;
  McpApiException(this.message);
  @override
  String toString() => message;
}

class McpTokenInfo {
  final String id;
  final String name;
  final String tokenPrefix;
  final List<String> scopes;
  final int? expiresAt;
  final int? lastUsedAt;
  final int createdAt;

  McpTokenInfo({
    required this.id,
    required this.name,
    required this.tokenPrefix,
    required this.scopes,
    this.expiresAt,
    this.lastUsedAt,
    required this.createdAt,
  });

  factory McpTokenInfo.fromJson(Map<String, dynamic> json) {
    return McpTokenInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      tokenPrefix: json['tokenPrefix'] as String? ?? '',
      scopes: (json['scopes'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      expiresAt: json['expiresAt'] as int?,
      lastUsedAt: json['lastUsedAt'] as int?,
      createdAt: json['createdAt'] as int? ?? 0,
    );
  }

  bool get canWrite => scopes.contains('tasks:write');

  String get scopeLabel {
    if (canWrite) return '读写';
    return '只读';
  }
}

class CreatedMcpToken {
  final String token;
  final McpTokenInfo info;
  CreatedMcpToken({required this.token, required this.info});
}

class McpApi {
  static Uri _uri(String path) =>
      Uri.parse('${SyncService.serverUrl}$path');

  static Map<String, String> get _headers => {
    'Authorization': 'Bearer ${SyncService.token}',
    'Content-Type': 'application/json',
  };

  static Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode == 404) {
      throw McpUnsupportedException();
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // fall through
    }
    throw McpApiException('服务器返回无效响应 (${response.statusCode})');
  }

  static Future<bool> isSupported() async {
    try {
      final response = await http
          .get(Uri.parse('${SyncService.serverUrl}/api/health'))
          .timeout(const Duration(seconds: 8));
      final data = _decode(response);
      return data['mcp'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<McpTokenInfo>> listTokens() async {
    final response = await http
        .get(_uri('/api/mcp/tokens'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpApiException(data['error'] as String? ?? '无法读取 MCP 令牌');
    }
    final tokens = data['tokens'] as List? ?? const [];
    return tokens
        .whereType<Map>()
        .map((item) => McpTokenInfo.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Future<CreatedMcpToken> createToken({
    required String name,
    required List<String> scopes,
    int? expiresInDays,
  }) async {
    final response = await http
        .post(
          _uri('/api/mcp/tokens'),
          headers: _headers,
          body: jsonEncode({
            'name': name,
            'scopes': scopes,
            'expiresInDays': expiresInDays,
          }),
        )
        .timeout(const Duration(seconds: 10));
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpApiException(data['error'] as String? ?? '创建令牌失败');
    }
    final token = data['token'] as String?;
    final info = data['info'];
    if (token == null || info is! Map) {
      throw McpApiException('创建令牌失败：服务器未返回令牌');
    }
    return CreatedMcpToken(
      token: token,
      info: McpTokenInfo.fromJson(Map<String, dynamic>.from(info)),
    );
  }

  static Future<void> revokeToken(String id) async {
    final response = await http
        .delete(_uri('/api/mcp/tokens/$id'), headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) {
      throw McpUnsupportedException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final data = _decode(response);
      throw McpApiException(data['error'] as String? ?? '撤销令牌失败');
    }
  }
}
