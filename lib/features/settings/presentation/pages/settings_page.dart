import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:focus_timer/data/database/app_database.dart';
import 'package:focus_timer/data/sync/sync_service.dart';
import 'package:focus_timer/features/timer/providers/timer_provider.dart';
import 'package:focus_timer/features/tasks/providers/task_provider.dart';

class SettingsPage extends ConsumerStatefulWidget {
  final VoidCallback onClose;

  const SettingsPage({super.key, required this.onClose});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late TextEditingController _focusDurationController;
  late TextEditingController _breakDurationController;
  late TextEditingController _longBreakDurationController;
  late TextEditingController _cyclesController;
  late TextEditingController _minDurationController;
  late TextEditingController _notificationTemplateController;
  bool _enableCycle = false;
  bool _autoStartNext = false;
  bool _autoStartBreak = false;
  bool _soundEnabled = true;
  String _notificationDuration = 'long';

  // Sync server state
  late TextEditingController _syncServerUrlController;
  late TextEditingController _syncUsernameController;
  late TextEditingController _syncPasswordController;
  bool _isLoggedIn = false;
  bool _isSyncing = false;
  String _syncStatus = '';
  int? _lastSyncTime;
  String _dbPath = '';

  // 同步服务器登录表单的 FocusNode，用于精确控制 Tab 跳转顺序
  late FocusNode _syncUrlFocusNode;
  late FocusNode _syncUsernameFocusNode;
  late FocusNode _syncPasswordFocusNode;
  late FocusNode _syncRegisterFocusNode;
  late FocusNode _syncLoginFocusNode;
  late FocusNode _syncLogoutFocusNode;

  @override
  void initState() {
    super.initState();
    final timerState = ref.read(timerProvider);
    _focusDurationController = TextEditingController(text: timerState.pomodoroConfig.focusDuration.toString());
    _breakDurationController = TextEditingController(text: timerState.pomodoroConfig.breakDuration.toString());
    _longBreakDurationController = TextEditingController(text: timerState.pomodoroConfig.longBreakDuration.toString());
    _cyclesController = TextEditingController(text: timerState.pomodoroConfig.cyclesBeforeLongBreak.toString());
    _minDurationController = TextEditingController(text: timerState.singleCoreConfig.minDuration.toString());
    _notificationTemplateController = TextEditingController(text: timerState.notificationTemplate);
    _enableCycle = timerState.pomodoroConfig.enableCycle;
    _autoStartNext = timerState.pomodoroConfig.autoStartNext;
    _autoStartBreak = timerState.pomodoroConfig.autoStartBreak;
    _soundEnabled = timerState.soundEnabled;
    _notificationDuration = timerState.notificationDuration;

    _syncServerUrlController = TextEditingController(text: SyncService.serverUrl);
    _syncUsernameController = TextEditingController();
    _syncPasswordController = TextEditingController();
    _isLoggedIn = SyncService.isLoggedIn;
    _lastSyncTime = SyncService.lastSyncTime > 0 ? SyncService.lastSyncTime : null;

    _syncUrlFocusNode = FocusNode();
    _syncUsernameFocusNode = FocusNode();
    _syncPasswordFocusNode = FocusNode();
    _syncRegisterFocusNode = FocusNode();
    _syncLoginFocusNode = FocusNode();
    _syncLogoutFocusNode = FocusNode();

    // 为 FocusNode 添加按键监听，拦截硬件 Tab 键，构建完整焦点链
    _setupFocusNode(_syncUrlFocusNode, _syncUsernameFocusNode);
    _setupFocusNode(_syncUsernameFocusNode, _syncPasswordFocusNode);
    _setupFocusNode(_syncPasswordFocusNode, _syncRegisterFocusNode);
    _setupFocusNode(_syncRegisterFocusNode, _syncLoginFocusNode);
    _setupFocusNode(_syncLoginFocusNode, _syncLogoutFocusNode);

    _loadDbPath();
  }

  void _setupFocusNode(FocusNode node, FocusNode nextNode) {
    node.onKeyEvent = (node, event) {
      if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
        // 如果按下了 Tab 键且没有按住 Shift（即向前跳转）
        if (!HardwareKeyboard.instance.isShiftPressed) {
          nextNode.requestFocus();
          return KeyEventResult.handled; // 关键：告诉系统我们已经处理了，不要执行默认跳转
        }
      }
      return KeyEventResult.ignored;
    };
  }

  Future<void> _loadDbPath() async {
    final path = await AppDatabase.getDbPath();
    if (mounted) setState(() => _dbPath = path);
  }

  @override
  void dispose() {
    _focusDurationController.dispose();
    _breakDurationController.dispose();
    _longBreakDurationController.dispose();
    _cyclesController.dispose();
    _minDurationController.dispose();
    _notificationTemplateController.dispose();
    _syncServerUrlController.dispose();
    _syncUsernameController.dispose();
    _syncPasswordController.dispose();
    // 释放登录表单 FocusNode
    _syncUrlFocusNode.dispose();
    _syncUsernameFocusNode.dispose();
    _syncPasswordFocusNode.dispose();
    _syncRegisterFocusNode.dispose();
    _syncLoginFocusNode.dispose();
    _syncLogoutFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timerState = ref.watch(timerProvider);
    final timerNotifier = ref.read(timerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  '设置',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkText : AppColors.lightText,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Settings content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                        // Single Core Section
                        _buildSectionTitle('🎯 单核工作法', isDark),
                        const SizedBox(height: 12),
                        _buildNumberSetting(
                          label: '最少专注时长（分钟）',
                          controller: _minDurationController,
                          onChanged: (value) {
                            final mins = int.tryParse(value) ?? 25;
                            timerNotifier.updateSingleCoreConfig(
                              timerState.singleCoreConfig.copyWith(minDuration: mins),
                            );
                          },
                          isDark: isDark,
                        ),

                        const SizedBox(height: 24),

                        // Pomodoro Section
                        _buildSectionTitle('🍅 番茄工作法', isDark),
                        const SizedBox(height: 12),
                        _buildNumberSetting(
                          label: '专注时长（分钟）',
                          controller: _focusDurationController,
                          onChanged: (value) {
                            final mins = int.tryParse(value) ?? 25;
                            timerNotifier.updatePomodoroConfig(
                              timerState.pomodoroConfig.copyWith(focusDuration: mins),
                            );
                          },
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildNumberSetting(
                          label: '休息时长（分钟）',
                          controller: _breakDurationController,
                          onChanged: (value) {
                            final mins = int.tryParse(value) ?? 5;
                            timerNotifier.updatePomodoroConfig(
                              timerState.pomodoroConfig.copyWith(breakDuration: mins),
                            );
                          },
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildSwitchSetting(
                          label: '启用循环模式',
                          value: timerState.pomodoroConfig.enableCycle,
                          onChanged: (value) {
                            setState(() => _enableCycle = value);
                            timerNotifier.updatePomodoroConfig(
                              timerState.pomodoroConfig.copyWith(enableCycle: value),
                            );
                          },
                          isDark: isDark,
                        ),

                        if (timerState.pomodoroConfig.enableCycle) ...[
                          const SizedBox(height: 12),
                          _buildNumberSetting(
                            label: '长休息时长（分钟）',
                            controller: _longBreakDurationController,
                            onChanged: (value) {
                              final mins = int.tryParse(value) ?? 15;
                              timerNotifier.updatePomodoroConfig(
                                timerState.pomodoroConfig.copyWith(longBreakDuration: mins),
                              );
                            },
                            isDark: isDark,
                          ),
                          const SizedBox(height: 12),
                          _buildNumberSetting(
                            label: '几轮后长休息',
                            controller: _cyclesController,
                            onChanged: (value) {
                              final cycles = int.tryParse(value) ?? 4;
                              timerNotifier.updatePomodoroConfig(
                                timerState.pomodoroConfig.copyWith(cyclesBeforeLongBreak: cycles),
                              );
                            },
                            isDark: isDark,
                          ),
                          const SizedBox(height: 12),
                          _buildSwitchSetting(
                            label: '自动开始下一轮',
                            value: timerState.pomodoroConfig.autoStartNext,
                            onChanged: (value) {
                              setState(() => _autoStartNext = value);
                              timerNotifier.updatePomodoroConfig(
                                timerState.pomodoroConfig.copyWith(autoStartNext: value),
                              );
                            },
                            isDark: isDark,
                          ),
                          const SizedBox(height: 12),
                          _buildSwitchSetting(
                            label: '专注后自动进入休息',
                            value: timerState.pomodoroConfig.autoStartBreak,
                            onChanged: (value) {
                              setState(() => _autoStartBreak = value);
                              timerNotifier.updatePomodoroConfig(
                                timerState.pomodoroConfig.copyWith(autoStartBreak: value),
                              );
                            },
                            isDark: isDark,
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Notification Section
                        _buildSectionTitle('🔔 通知', isDark),
                        const SizedBox(height: 12),
                        _buildSelectSetting(
                          label: '通知持续时间',
                          value: _notificationDuration,
                          options: const [
                            {'value': 'short', 'label': '短（系统默认）'},
                            {'value': 'long', 'label': '长（默认值）'},
                            {'value': 'persistent', 'label': '常驻（闹钟模式）'},
                          ],
                          onChanged: (value) {
                            setState(() => _notificationDuration = value);
                            timerNotifier.setNotificationDuration(value);
                          },
                          isDark: isDark,
                        ),
                        const SizedBox(height: 12),
                        _buildTextSettingWithHints(
                          label: '通知模板',
                          controller: _notificationTemplateController,
                          onChanged: (value) {
                            timerNotifier.setNotificationTemplate(value);
                          },
                          hint: '计时完成！{task}',
                          placeholderHints: const [
                            {'key': '{task}', 'desc': '专注内容'},
                            {'key': '{mode}', 'desc': '计时模式'},
                            {'key': '{duration}', 'desc': '计时时长'},
                          ],
                          isDark: isDark,
                        ),

                        const SizedBox(height: 24),

                        // General Section
                        _buildSectionTitle('⚙ 通用', isDark),
                        const SizedBox(height: 12),
                        _buildSwitchSetting(
                          label: '提示音',
                          value: _soundEnabled,
                          onChanged: (value) {
                            setState(() => _soundEnabled = value);
                            timerNotifier.toggleSound();
                          },
                          isDark: isDark,
                        ),

                        const SizedBox(height: 24),

                        // Data Management Section
                        _buildSectionTitle('💾 数据管理', isDark),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '数据库：',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _dbPath,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                                softWrap: true,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildButtonRow([
                          _SettingButton(
                            label: '导出备份',
                            onPressed: _handleExport,
                            isPrimary: true,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _SettingButton(
                            label: '导入恢复',
                            onPressed: _handleImport,
                            isPrimary: false,
                            isDark: isDark,
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text(
                          '导入将覆盖当前数据，请先导出备份',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Cloud Sync Section
                        _buildSectionTitle('☁ 同步服务器', isDark),
                        const SizedBox(height: 12),
                        // 使用 FocusTraversalGroup 隔离整个同步区域的焦点
                        FocusTraversalGroup(
                          child: Column(
                            children: [
                              // 服务器地址
                              _buildTextSetting(
                                label: '服务器地址',
                                controller: _syncServerUrlController,
                                onChanged: (value) {},
                                hint: 'http://1.12.46.222:6677',
                                isDark: isDark,
                                enabled: !_isLoggedIn,
                                focusNode: _syncUrlFocusNode,
                                nextFocusNode: _syncUsernameFocusNode,
                              ),
                              const SizedBox(height: 12),
                              // 用户名
                              _buildTextSetting(
                                label: '用户名',
                                controller: _syncUsernameController,
                                onChanged: (value) {},
                                hint: '用户名',
                                isDark: isDark,
                                enabled: !_isLoggedIn,
                                focusNode: _syncUsernameFocusNode,
                                nextFocusNode: _syncPasswordFocusNode,
                              ),
                              const SizedBox(height: 12),
                              // 密码
                              _buildTextSetting(
                                label: '密码',
                                controller: _syncPasswordController,
                                onChanged: (value) {},
                                hint: '密码',
                                isDark: isDark,
                                enabled: !_isLoggedIn,
                                obscureText: true,
                                focusNode: _syncPasswordFocusNode,
                                nextFocusNode: _syncRegisterFocusNode,
                                onSubmitted: (_) => _isLoggedIn ? null : _handleLogin(),
                              ),
                              const SizedBox(height: 12),
                              _buildButtonRow([
                                _SettingButton(
                                  label: '注册',
                                  onPressed: _isLoggedIn ? null : _handleRegister,
                                  isPrimary: false,
                                  isDark: isDark,
                                  focusNode: _syncRegisterFocusNode,
                                ),
                                const SizedBox(width: 8),
                                _SettingButton(
                                  label: '登录',
                                  onPressed: _isLoggedIn ? null : _handleLogin,
                                  isPrimary: true,
                                  isDark: isDark,
                                  focusNode: _syncLoginFocusNode,
                                ),
                                const SizedBox(width: 8),
                                _SettingButton(
                                  label: '登出',
                                  onPressed: _isLoggedIn ? _handleLogout : null,
                                  isPrimary: false,
                                  isDanger: true,
                                  isDark: isDark,
                                  focusNode: _syncLogoutFocusNode,
                                ),
                              ]),
                            ],
                          ),
                        ),
                        if (_isLoggedIn && _lastSyncTime != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            '上次同步：${DateTime.fromMillisecondsSinceEpoch(_lastSyncTime!).toString()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _SettingButton(
                          label: _isSyncing ? '同步中...' : '立即同步',
                          onPressed: _isLoggedIn && !_isSyncing ? _handleSyncNow : null,
                          isPrimary: true,
                          isAccent: true,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '多设备数据自动合并，最新修改优先',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildButtonRow([
                          _SettingButton(
                            label: '调试信息',
                            onPressed: _handleDebugInfo,
                            isPrimary: false,
                            isDark: isDark,
                          ),
                          const SizedBox(width: 8),
                          _SettingButton(
                            label: '测试下载',
                            onPressed: _handleTestDownload,
                            isPrimary: false,
                            isDark: isDark,
                          ),
                        ]),

                        if (_syncStatus.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              children: [
                                if (_isSyncing)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _syncStatus,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark ? AppColors.darkText : AppColors.lightText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Current config summary
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '当前配置：',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                  color: isDark ? AppColors.darkText : AppColors.lightText,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _getConfigSummary(timerState),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        // Version info
                        Center(
                          child: Text(
                            'v1.0.1',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ),
              ],
            ),
          ),
        ),
      ],
    ),
  ); // End of Container
} // End of build

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkText : AppColors.lightText,
      ),
    );
  }



  Widget _buildNumberSetting({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    required bool isDark,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
        ),
        SizedBox(
          width: 70,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchSetting({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          height: 24,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF7C3AED),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectSetting({
    required String label,
    required String value,
    required List<Map<String, String>> options,
    required ValueChanged<String> onChanged,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: DropdownButton<String>(
            value: value,
            underline: Container(),
            isDense: true,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
            dropdownColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            items: options.map((opt) => DropdownMenuItem(
              value: opt['value'],
              child: Text(opt['label']!),
            )).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTextSetting({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? hint,
    required bool isDark,
    bool enabled = true,
    bool obscureText = false,
    // 可选的 FocusNode，用于精确控制焦点顺序
    FocusNode? focusNode,
    // Tab / Next 时跳转到的目标 FocusNode
    FocusNode? nextFocusNode,
    // Enter 键提交回调（密码框登录用）
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkText : AppColors.lightText,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscureText,
          focusNode: focusNode,
          // 有 nextFocusNode 时显示 next 动作键，否则显示 done
          textInputAction: nextFocusNode != null
              ? TextInputAction.next
              : (onSubmitted != null ? TextInputAction.go : TextInputAction.done),
          style: TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          // Tab / Next 时精确跳转到指定输入框，避免焦点飘到侧边栏任务清单
          onEditingComplete: () {
            if (nextFocusNode != null) {
              nextFocusNode.requestFocus();
            } else {
              focusNode?.unfocus();
            }
          },
        ),
      ],
    );
  }

  Widget _buildTextSettingWithHints({
    required String label,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    String? hint,
    required List<Map<String, String>> placeholderHints,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkText : AppColors.lightText,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          onChanged: onChanged,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            Text(
              '可用占位符：',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            ...placeholderHints.map((p) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${p['key']}（${p['desc']}）',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            )),
          ],
        ),
      ],
    );
  }

  String _getConfigSummary(TimerState timerState) {
    if (timerState.timerMode == TimerMode.singleCore) {
      return '单核工作法 · 最少 ${timerState.singleCoreConfig.minDuration} 分钟';
    }
    final pomodoro = timerState.pomodoroConfig;
    final parts = <String>[];
    parts.add('番茄工作法');
    parts.add('专注 ${pomodoro.focusDuration}min');
    parts.add('休息 ${pomodoro.breakDuration}min');
    if (pomodoro.enableCycle) {
      parts.add('长休息 ${pomodoro.longBreakDuration}min');
      parts.add('每${pomodoro.cyclesBeforeLongBreak}轮长休息');
      if (pomodoro.autoStartNext) parts.add('自动开始下一轮');
      if (pomodoro.autoStartBreak) parts.add('专注后自动进入休息');
    }
    return parts.join(' · ');
  }

  /// 构建一个按钮行，并确保其中的 _SettingButton 能够平分宽度
  Widget _buildButtonRow(List<Widget> children) {
    return Row(
      children: children.map((child) {
        if (child is _SettingButton) {
          // 只有在 Row 中才使用 Expanded，防止在 Column 中使用导致布局约束错误
          return Expanded(child: child);
        }
        return child;
      }).toList(),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _handleRegister() async {
    if (_syncServerUrlController.text.isEmpty ||
        _syncUsernameController.text.isEmpty ||
        _syncPasswordController.text.isEmpty) {
      _showSnackBar('请填写完整信息', isError: true);
      return;
    }

    try {
      await SyncService.setServerUrl(_syncServerUrlController.text);
      final result = await SyncService.register(
        username: _syncUsernameController.text,
        password: _syncPasswordController.text,
      );

      if (result.success) {
        setState(() {
          _isLoggedIn = true;
          _syncStatus = '注册成功';
        });
        _showSnackBar('注册成功');
      } else {
        setState(() => _syncStatus = result.error ?? '注册失败');
        _showSnackBar(result.error ?? '注册失败', isError: true);
      }
    } catch (e) {
      setState(() => _syncStatus = '发生错误');
      _showSnackBar('错误: $e', isError: true);
    }
    _clearStatusAfterDelay();
  }

  Future<void> _handleLogin() async {
    if (_syncServerUrlController.text.isEmpty ||
        _syncUsernameController.text.isEmpty ||
        _syncPasswordController.text.isEmpty) {
      _showSnackBar('请填写完整信息', isError: true);
      return;
    }

    try {
      await SyncService.setServerUrl(_syncServerUrlController.text);
      final result = await SyncService.login(
        username: _syncUsernameController.text,
        password: _syncPasswordController.text,
      );

      if (result.success) {
        setState(() {
          _isLoggedIn = true;
          _syncStatus = '登录成功';
        });
        _showSnackBar('登录成功');
      } else {
        setState(() => _syncStatus = result.error ?? '登录失败');
        _showSnackBar(result.error ?? '登录失败', isError: true);
      }
    } catch (e) {
      setState(() => _syncStatus = '发生错误');
      _showSnackBar('错误: $e', isError: true);
    }
    _clearStatusAfterDelay();
  }

  Future<void> _handleLogout() async {
    try {
      await SyncService.logout();
      setState(() {
        _isLoggedIn = false;
        _syncStatus = '已登出';
      });
      _showSnackBar('已登出');
    } catch (e) {
      _showSnackBar('登出失败: $e', isError: true);
    }
    _clearStatusAfterDelay();
  }

  Future<void> _handleSyncNow() async {
    if (!SyncService.isLoggedIn) {
      _showSnackBar('请先登录', isError: true);
      return;
    }

    setState(() {
      _isSyncing = true;
      _syncStatus = '同步中...';
    });

    try {
      final result = await SyncService.fullSync();

      if (result.tokenExpired) {
        setState(() {
          _isLoggedIn = false;
          _syncStatus = '登录已过期，请重新登录';
        });
        _showSnackBar('登录已过期，请重新登录', isError: true);
      } else if (result.success) {
        final lastSync = SyncService.lastSyncTime;
        setState(() {
          _lastSyncTime = lastSync > 0 ? lastSync : null;
          _syncStatus = '同步完成';
        });
        // Refresh tasks after sync
        ref.read(taskProvider.notifier).loadTasks();
      } else {
        setState(() => _syncStatus = '同步失败或未配置');
      }
    } catch (e) {
      setState(() => _syncStatus = '同步失败');
    }

    setState(() => _isSyncing = false);
    _clearStatusAfterDelay();
  }

  Future<void> _handleDebugInfo() async {
    final info = await AppDatabase.getDebugInfo();
    setState(() {
      _syncStatus = 'DB:${info['dbOpen']} lists:${info['lists']} tasks:${info['tasks']} sessions:${info['sessions']}';
    });
    _clearStatusAfterDelay(5000);
  }

  Future<void> _handleTestDownload() async {
    setState(() => _syncStatus = '测试下载中...');
    try {
      final result = await AppDatabase.runDownloadTest();
      ref.read(taskProvider.notifier).loadTasks();
      setState(() {
        _syncStatus = '测试完成: lists=${result['listsCount']} tasks=${result['tasksCount']}';
      });
    } catch (e) {
      setState(() => _syncStatus = '测试失败: $e');
    }
    _clearStatusAfterDelay();
  }

  Future<void> _handleExport() async {
    setState(() => _syncStatus = '导出功能需要平台文件选择器支持');
    _clearStatusAfterDelay();
  }

  Future<void> _handleImport() async {
    setState(() => _syncStatus = '导入功能需要平台文件选择器支持');
    _clearStatusAfterDelay();
  }

  void _clearStatusAfterDelay([int milliseconds = 3000]) {
    Future.delayed(Duration(milliseconds: milliseconds), () {
      if (mounted) setState(() => _syncStatus = '');
    });
  }
}

class _SettingButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isPrimary;
  final bool isAccent;
  final bool isDanger;
  final bool isDark;
  final FocusNode? focusNode;

  const _SettingButton({
    required this.label,
    required this.onPressed,
    required this.isPrimary,
    this.isAccent = false,
    this.isDanger = false,
    required this.isDark,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDanger
        ? Colors.red
        : isAccent
            ? const Color(0xFF4FC3F7)
            : isPrimary
                ? const Color(0xFF7C3AED)
                : Colors.transparent;

    final textColor = isPrimary || isAccent || isDanger
        ? Colors.white
        : isDark ? AppColors.darkText : AppColors.lightText;

    final borderColor = isDanger
        ? Colors.red
        : isPrimary || isAccent
            ? bgColor
            : isDark ? AppColors.darkBorder : AppColors.lightBorder;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        focusNode: focusNode,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: borderColor),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}