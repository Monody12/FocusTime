import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/data/sync/mcp_api.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';

class McpTokenSettings extends StatefulWidget {
  const McpTokenSettings({super.key});

  @override
  State<McpTokenSettings> createState() => _McpTokenSettingsState();
}

class _McpTokenSettingsState extends State<McpTokenSettings> {
  bool _loading = true;
  bool _supported = false;
  String? _error;
  List<McpTokenInfo> _tokens = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!SyncService.isLoggedIn) {
      setState(() {
        _loading = false;
        _supported = false;
        _tokens = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supported = await McpApi.isSupported();
      if (!supported) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _supported = false;
        });
        return;
      }
      final tokens = await McpApi.listTokens();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _supported = true;
        _tokens = tokens;
      });
    } on McpUnsupportedException {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _supported = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : context.appColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _createToken() async {
    final nameController = TextEditingController(text: 'MCP 客户端');
    var allowWrite = false;
    var expireDays = 90;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('新建 MCP 令牌'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '名称'),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('允许写入任务'),
                      subtitle: const Text('默认只读。写入会同步到所有设备。'),
                      value: allowWrite,
                      onChanged: (value) =>
                          setDialogState(() => allowWrite = value),
                    ),
                    DropdownButtonFormField<int>(
                      key: ValueKey(expireDays),
                      initialValue: expireDays,
                      decoration: const InputDecoration(labelText: '有效期'),
                      items: const [
                        DropdownMenuItem(value: 30, child: Text('30 天')),
                        DropdownMenuItem(value: 90, child: Text('90 天')),
                        DropdownMenuItem(value: 365, child: Text('365 天')),
                        DropdownMenuItem(value: 0, child: Text('不过期')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => expireDays = value);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('创建'),
                ),
              ],
            );
          },
        );
      },
    );
    final name = nameController.text.trim();
    nameController.dispose();
    if (confirmed != true || name.isEmpty) return;

    final scopes = allowWrite
        ? const ['tasks:read', 'tasks:write', 'sessions:read']
        : const ['tasks:read', 'sessions:read'];
    try {
      final created = await McpApi.createToken(
        name: name,
        scopes: scopes,
        expiresInDays: expireDays == 0 ? null : expireDays,
      );
      if (!mounted) return;
      await _reload();
      await _showCreatedToken(created.token);
    } catch (e) {
      _snack(e.toString(), isError: true);
    }
  }

  Future<void> _showCreatedToken(String token) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('请立即复制令牌'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('此明文只显示一次，关闭后无法再查看。'),
              const SizedBox(height: 12),
              SelectableText(token),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: token));
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              },
              child: const Text('复制并关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _revoke(McpTokenInfo token) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('撤销令牌'),
          content: Text('撤销后，使用「${token.name}」的 MCP 客户端将立即失效。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('撤销'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await McpApi.revokeToken(token.id);
      _snack('令牌已撤销');
      await _reload();
    } catch (e) {
      _snack(e.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!SyncService.isLoggedIn) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          '🔌 MCP 访问令牌',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.appColors.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '给 Claude、Cursor 等 MCP 客户端使用。令牌只绑定当前同步账号，默认只读。',
          style: TextStyle(fontSize: 11, color: context.appColors.textSecondary),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (!_supported)
          Text(
            '当前同步服务器尚未启用 MCP。升级 server/ 后即可在此生成令牌。',
            style: TextStyle(
              fontSize: 12,
              color: context.appColors.textSecondary,
            ),
          )
        else ...[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          if (_tokens.isEmpty)
            Text(
              '还没有令牌。',
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.textSecondary,
              ),
            ),
          ..._tokens.map((token) {
            final expiry = token.expiresAt == null
                ? '不过期'
                : '到期 ${AppTime.formatDateTimeFromMilliseconds(token.expiresAt!)}';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.appColors.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.appColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          token.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.appColors.text,
                          ),
                        ),
                        Text(
                          '${token.tokenPrefix}… · ${token.scopeLabel} · $expiry',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => _revoke(token),
                    child: Text(
                      '撤销',
                      style: TextStyle(
                        color: isDark ? Colors.redAccent : Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _createToken,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建令牌'),
            ),
          ),
        ],
      ],
    );
  }
}
