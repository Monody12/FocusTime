import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:focus_my_time/core/providers/theme_provider.dart';
import 'package:focus_my_time/core/providers/time_zone_provider.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/data/sync/sync_service.dart';
import 'package:focus_my_time/features/timer/providers/timer_provider.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';
import 'package:focus_my_time/features/tasks/services/reminder_service.dart';
import 'package:focus_my_time/features/calendar/services/calendar_service.dart';
import 'package:focus_my_time/features/ai_assistant/services/deepseek_api_client.dart';
import 'package:focus_my_time/core/providers/package_info_provider.dart';
import 'package:focus_my_time/features/update/presentation/widgets/update_dialog.dart';
import 'package:focus_my_time/features/update/services/update_service.dart';
import 'package:focus_my_time/features/settings/presentation/widgets/archived_items_dialog.dart';

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
  late TextEditingController _snoozeDurationController;
  bool _soundEnabled = true;
  String _notificationDuration = 'long';

  // AI API key
  late TextEditingController _apiKeyController;

  // Sync server state
  late TextEditingController _syncServerUrlController;
  late TextEditingController _syncUsernameController;
  late TextEditingController _syncPasswordController;
  bool _isLoggedIn = false;
  bool _isSyncing = false;
  String _syncStatus = '';
  int? _lastSyncTime;
  String _dbPath = '';
  Map<String, String> _permissionStatus = {};
  bool _calendarSyncEnabled = false;
  bool _obscurePassword = true;

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
    _focusDurationController = TextEditingController(
        text: timerState.pomodoroConfig.focusDuration.toString());
    _breakDurationController = TextEditingController(
        text: timerState.pomodoroConfig.breakDuration.toString());
    _longBreakDurationController = TextEditingController(
        text: timerState.pomodoroConfig.longBreakDuration.toString());
    _cyclesController = TextEditingController(
        text: timerState.pomodoroConfig.cyclesBeforeLongBreak.toString());
    _minDurationController = TextEditingController(
        text: timerState.singleCoreConfig.minDuration.toString());
    _notificationTemplateController =
        TextEditingController(text: timerState.notificationTemplate);
    _snoozeDurationController = TextEditingController(
        text: timerState.snoozeDurationMinutes.toString());
    _soundEnabled = timerState.soundEnabled;
    _notificationDuration = timerState.notificationDuration;

    _syncServerUrlController =
        TextEditingController(text: SyncService.serverUrl);
    _syncUsernameController = TextEditingController(text: SyncService.username);
    _syncPasswordController =
        TextEditingController(text: SyncService.fakePassword);
    _isLoggedIn = SyncService.isLoggedIn;
    _lastSyncTime =
        SyncService.lastSyncTime > 0 ? SyncService.lastSyncTime : null;

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
    _loadPermissions();
    _loadCalendarStatus();
    _apiKeyController =
        TextEditingController(text: DeepSeekApiClient.apiKey ?? '');
  }

  Future<void> _loadCalendarStatus() async {
    final enabled = await CalendarService.isEnabled();
    if (mounted) setState(() => _calendarSyncEnabled = enabled);
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    await DeepSeekApiClient.setApiKey(key);
    _showSnackBar(key.isEmpty ? '已清除 API 密钥' : 'API 密钥已保存');
  }

  Future<void> _testApiConnection() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      _showSnackBar('请先输入 API 密钥', isError: true);
      return;
    }
    await DeepSeekApiClient.setApiKey(key);
    _showSnackBar('正在测试连接...');
    final ok = await DeepSeekApiClient.testConnection();
    _showSnackBar(ok ? '连接成功！API 密钥有效' : '连接失败，请检查密钥', isError: !ok);
  }

  Future<void> _loadPermissions() async {
    final status = await ReminderService.getPermissionStatus();
    if (mounted) setState(() => _permissionStatus = status);
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
    _snoozeDurationController.dispose();
    _apiKeyController.dispose();
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
    final timerMode = ref.watch(timerProvider.select((s) => s.timerMode));
    final singleCoreConfig =
        ref.watch(timerProvider.select((s) => s.singleCoreConfig));
    final pomodoroConfig =
        ref.watch(timerProvider.select((s) => s.pomodoroConfig));
    final soundEnabled = ref.watch(timerProvider.select((s) => s.soundEnabled));
    final notificationDuration =
        ref.watch(timerProvider.select((s) => s.notificationDuration));
    final notificationTemplate =
        ref.watch(timerProvider.select((s) => s.notificationTemplate));
    final snoozeDurationMinutes =
        ref.watch(timerProvider.select((s) => s.snoozeDurationMinutes));
    final rememberModeChoice =
        ref.watch(timerProvider.select((s) => s.rememberModeChoice));
    final preferredModeWhenOverdue =
        ref.watch(timerProvider.select((s) => s.preferredModeWhenOverdue));
    final timeZoneMode = ref.watch(timeZoneProvider);
    final themeScheme = ref.watch(themeSchemeProvider);

    // 构建一个不包含流逝时间的状态对象供当前页面使用，彻底避免计时器走字导致的页面每秒重绘
    final timerState = TimerState(
      timerMode: timerMode,
      singleCoreConfig: singleCoreConfig,
      pomodoroConfig: pomodoroConfig,
      soundEnabled: soundEnabled,
      notificationDuration: notificationDuration,
      notificationTemplate: notificationTemplate,
      snoozeDurationMinutes: snoozeDurationMinutes,
      rememberModeChoice: rememberModeChoice,
      preferredModeWhenOverdue: preferredModeWhenOverdue,
    );
    final timerNotifier = ref.read(timerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      color: context.appColors.background,
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
                    color: context.appColors.text,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(AppIcons.close),
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
                          timerState.pomodoroConfig
                              .copyWith(longBreakDuration: mins),
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
                          timerState.pomodoroConfig
                              .copyWith(cyclesBeforeLongBreak: cycles),
                        );
                      },
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildSwitchSetting(
                      label: '自动开始下一轮',
                      value: timerState.pomodoroConfig.autoStartNext,
                      onChanged: (value) {
                        timerNotifier.updatePomodoroConfig(
                          timerState.pomodoroConfig
                              .copyWith(autoStartNext: value),
                        );
                      },
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildSwitchSetting(
                      label: '专注后自动进入休息',
                      value: timerState.pomodoroConfig.autoStartBreak,
                      onChanged: (value) {
                        timerNotifier.updatePomodoroConfig(
                          timerState.pomodoroConfig
                              .copyWith(autoStartBreak: value),
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
                  const SizedBox(height: 12),
                  _buildNumberSetting(
                    label: '稍后提醒时长（分钟）',
                    controller: _snoozeDurationController,
                    onChanged: (value) {
                      final mins = int.tryParse(value) ?? 10;
                      timerNotifier.setSnoozeDuration(mins);
                    },
                    isDark: isDark,
                  ),

                  const SizedBox(height: 24),

                  // General Section
                  _buildSectionTitle('⚙ 通用', isDark),
                  const SizedBox(height: 12),
                  _buildTimeZoneSetting(timeZoneMode, isDark),
                  const SizedBox(height: 12),
                  _buildSelectSetting(
                    label: '主题配色',
                    value: themeScheme.id,
                    options: AppTheme.schemes
                        .map((scheme) => {
                              'value': scheme.id,
                              'label': scheme.label,
                            })
                        .toList(),
                    onChanged: (value) async {
                      try {
                        await ref
                            .read(themeSchemeProvider.notifier)
                            .setThemeScheme(value);
                        _showSnackBar('主题配色已切换');
                      } catch (e) {
                        _showSnackBar('主题配色保存失败: $e', isError: true);
                      }
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildSwitchSetting(
                    label: '提示音',
                    value: _soundEnabled,
                    onChanged: (value) {
                      setState(() => _soundEnabled = value);
                      timerNotifier.toggleSound();
                      _showSnackBar(value ? '提示音已开启' : '提示音已关闭');
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildSelectSetting(
                    label: '任务超时后默认模式',
                    value: timerState.preferredModeWhenOverdue.isEmpty
                        ? 'ask'
                        : timerState.preferredModeWhenOverdue,
                    options: const [
                      {'value': 'ask', 'label': '每次询问'},
                      {'value': 'singleCore', 'label': '单核工作法'},
                      {'value': 'pomodoro', 'label': '番茄工作法'},
                    ],
                    onChanged: (value) {
                      timerNotifier.setPreferredModeWhenOverdue(value);
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildSwitchSetting(
                    label: '记住超时后的模式选择',
                    value: timerState.rememberModeChoice,
                    onChanged: (value) {
                      timerNotifier.setRememberModeChoice(value);
                    },
                    isDark: isDark,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Text(
                      '启用后，选择模式时会记住您的选择，下次超时自动使用该模式',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Data Management Section
                  _buildSectionTitle('💾 数据管理', isDark),
                  const SizedBox(height: 12),
                  _SettingButton(
                    label: '管理归档任务与清单',
                    onPressed: () => ArchivedItemsDialog.show(context),
                    isPrimary: false,
                    isAccent: true,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.appColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: context.appColors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '数据库：',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.appColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _dbPath,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: context.appColors.textSecondary,
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
                      color: context.appColors.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Calendar Sync Debug Section
                  _buildSectionTitle('📅 日历同步高级设置', isDark),
                  const SizedBox(height: 12),
                  Text(
                    '如果您的日历出现重复事件或无法修改的问题，您可以使用此按钮强制清理系统中的所有相关日历并重新同步当前有效任务。',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingButton(
                    label: '清理日历系统并强制刷新',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('强制清理日历'),
                          content: const Text(
                              '此操作将删除系统中所有名为 "FocusMyTime 提醒" 的日历，并重新同步当前的提醒任务。这需要几秒钟的时间。确定继续吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(c).pop(false),
                              child: const Text('取消'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.of(c).pop(true),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red),
                              child: const Text('确定清理',
                                  style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                      );

                      if (confirm == true) {
                        try {
                          // 展示一个全局 Loading
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (c) => const Center(
                                child: CircularProgressIndicator()),
                          );

                          final tasks = ref.read(taskProvider).tasks;
                          await CalendarService.forceRebuildCalendar(tasks);

                          if (mounted) {
                            Navigator.of(context).pop(); // 关闭 loading
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('日历系统已清理并重新同步完成！')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            Navigator.of(context).pop(); // 关闭 loading
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('清理失败: $e')),
                            );
                          }
                        }
                      }
                    },
                    isPrimary: false,
                    isDark: isDark,
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
                          obscureText: _obscurePassword,
                          isPassword: true,
                          onPasswordVisibilityToggle: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                              if (!_obscurePassword &&
                                  _syncPasswordController.text ==
                                      SyncService.fakePassword) {
                                final decrypted = SyncService.realPassword;
                                if (decrypted.isNotEmpty) {
                                  _syncPasswordController.text = decrypted;
                                }
                              }
                            });
                          },
                          focusNode: _syncPasswordFocusNode,
                          nextFocusNode: _syncRegisterFocusNode,
                          onSubmitted: (_) =>
                              _isLoggedIn ? null : _handleLogin(),
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
                      '上次同步：${AppTime.formatDateTimeFromMilliseconds(_lastSyncTime!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _SettingButton(
                    label: _isSyncing ? '同步中...' : '立即同步',
                    onPressed:
                        _isLoggedIn && !_isSyncing ? _handleSyncNow : null,
                    isPrimary: true,
                    isAccent: true,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '多设备数据自动合并，最新修改优先',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.appColors.textSecondary,
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
                        color: context.appColors.surface,
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
                                color: context.appColors.text,
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
                      color: context.appColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: context.appColors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '当前配置：',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            color: context.appColors.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _getConfigSummary(timerState),
                            style: TextStyle(
                              fontSize: 13,
                              color: context.appColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Debug Section
                  _buildSectionTitle('🛠 调试与权限', isDark),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.appColors.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: context.appColors.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ..._permissionStatus.entries.map((e) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${e.key}:',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.appColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    e.value,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: e.value.contains('granted')
                                          ? context.appColors.success
                                          : Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildButtonRow([
                    _SettingButton(
                      label: '检查权限',
                      onPressed: () async {
                        try {
                          await ReminderService.initialize();
                          final granted = await ReminderService
                              .requestNotificationPermission();
                          await _loadPermissions();
                          if (granted) {
                            _showSnackBar('通知权限已开启，权限状态已更新');
                          } else {
                            await ReminderService.openNotificationSettings();
                            _showSnackBar('通知仍被系统拒绝，已打开 macOS 通知设置',
                                isError: true);
                          }
                        } catch (e) {
                          _showSnackBar('检查权限失败: $e', isError: true);
                        }
                      },
                      isPrimary: false,
                      isDark: isDark,
                    ),
                    _SettingButton(
                      label: '精确闹钟',
                      onPressed: () async {
                        if (Platform.isAndroid) {
                          try {
                            await ReminderService.requestExactAlarmPermission();
                            await _loadPermissions();
                            _showSnackBar('精确闹钟权限请求完成');
                          } catch (e) {
                            _showSnackBar('请求精确闹钟权限失败: $e', isError: true);
                          }
                        } else {
                          _showSnackBar('精确闹钟权限仅在 Android 平台上需要，当前平台无需配置。');
                        }
                      },
                      isPrimary: false,
                      isDark: isDark,
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _buildButtonRow([
                    _SettingButton(
                      label: '电池优化',
                      onPressed: () async {
                        if (Platform.isAndroid) {
                          try {
                            await ReminderService
                                .requestIgnoreBatteryOptimizations();
                            await _loadPermissions();
                            _showSnackBar('忽略电池优化请求完成');
                          } catch (e) {
                            _showSnackBar('请求忽略电池优化失败: $e', isError: true);
                          }
                        } else {
                          _showSnackBar('忽略电池优化设置仅在 Android 平台上需要，当前平台无需配置。');
                        }
                      },
                      isPrimary: false,
                      isDark: isDark,
                    ),
                    _SettingButton(
                      label: '发送测试通知',
                      onPressed: () async {
                        try {
                          await ReminderService.showImmediateTestNotification();
                          await _loadPermissions();
                          _showSnackBar('测试通知已发送，请检查系统通知中心');
                        } catch (e) {
                          await _loadPermissions();
                          _showSnackBar('发送测试通知失败，已打开通知设置: $e', isError: true);
                        }
                      },
                      isPrimary: false,
                      isDark: isDark,
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _buildButtonRow([
                    _SettingButton(
                      label: '强制清理日历',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('强制清理日历'),
                            content: const Text(
                                '此操作将删除系统中所有名为 "FocusMyTime 提醒" 的日历，并重新同步当前的提醒任务。这需要几秒钟的时间。确定继续吗？'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(c).pop(false),
                                child: const Text('取消'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.of(c).pop(true),
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                child: const Text('确定清理',
                                    style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          try {
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (c) => const Center(
                                  child: CircularProgressIndicator()),
                            );

                            final tasks = ref.read(taskProvider).tasks;
                            await CalendarService.forceRebuildCalendar(tasks);

                            if (mounted) {
                              Navigator.of(context).pop(); // 关闭 loading
                              _showSnackBar('日历系统已清理并重新同步完成！');
                            }
                          } catch (e) {
                            if (mounted) {
                              Navigator.of(context).pop(); // 关闭 loading
                              _showSnackBar('清理失败: $e', isError: true);
                            }
                          }
                        }
                      },
                      isPrimary: false,
                      isDark: isDark,
                    ),
                  ]),
                  const SizedBox(height: 8),
                  _buildButtonRow([
                    _SettingButton(
                      label: '测试系统闹钟',
                      onPressed: () async {
                        try {
                          await ReminderService.triggerTestAlarm();
                          _showSnackBar('测试系统闹钟已发送');
                        } catch (e) {
                          _showSnackBar('触发测试系统闹钟失败: $e', isError: true);
                        }
                      },
                      isPrimary: false,
                      isAccent: true,
                      isDark: isDark,
                    ),
                    _SettingButton(
                      label: '测试日历同步',
                      onPressed: () async {
                        try {
                          final success =
                              await CalendarService.triggerTestSync();
                          _showSnackBar(
                              success ? '测试事件已添加至日历' : '日历同步测试失败，请检查权限');
                        } catch (e) {
                          _showSnackBar('测试日历同步异常: $e', isError: true);
                        }
                      },
                      isPrimary: false,
                      isAccent: true,
                      isDark: isDark,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // Advanced Section
                  _buildSectionTitle('🚀 高级功能', isDark),
                  const SizedBox(height: 12),
                  _buildSwitchSetting(
                    label: '同步任务到系统日历',
                    value: _calendarSyncEnabled,
                    onChanged: (value) async {
                      await CalendarService.setEnabled(value);
                      setState(() => _calendarSyncEnabled = value);
                      if (value) {
                        // 立即同步所有现有任务
                        final taskState = ref.read(taskProvider);
                        CalendarService.refreshAll(taskState.tasks);
                      }
                    },
                    isDark: isDark,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Text(
                      '启用后，有提醒时间的任务将自动同步到手机系统日历中，提供更可靠的提醒。',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // AI 助手配置
                  _buildSectionTitle('🤖 AI 助手', isDark),
                  const SizedBox(height: 12),
                  _buildTextSetting(
                    label: 'DeepSeek API Key',
                    controller: _apiKeyController,
                    hint: '输入 API 密钥',
                    isDark: isDark,
                    obscureText: true,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _SettingButton(
                        label: '保存密钥',
                        onPressed: () => _saveApiKey(),
                        isPrimary: true,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _SettingButton(
                        label: '测试连接',
                        onPressed: () => _testApiConnection(),
                        isPrimary: true,
                        isAccent: true,
                        isDark: isDark,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8, left: 2),
                    child: Text(
                      'API 密钥存储在本地设备中，请勿在不安全的环境中使用。'
                      '获取密钥: platform.deepseek.com/api_keys',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Version info
                  Center(
                    child: Column(
                      children: [
                        ref.watch(packageInfoProvider).when(
                              data: (info) => Text(
                                'v${info.version}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.appColors.textSecondary,
                                ),
                              ),
                              loading: () => const SizedBox.shrink(),
                              error: (_, __) => const SizedBox.shrink(),
                            ),
                        const SizedBox(height: 8),
                        _SettingButton(
                          label: '检查更新',
                          onPressed: _handleCheckForUpdates,
                          isPrimary: false,
                          isAccent: true,
                          isDark: isDark,
                        ),
                      ],
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
        color: context.appColors.text,
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
              color: context.appColors.text,
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
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
              color: context.appColors.text,
            ),
          ),
        ),
        SizedBox(
          width: 44,
          height: 24,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeColor: context.appColors.accent,
          ),
        ),
      ],
    );
  }

  Widget _buildTimeZoneSetting(AppTimeZoneMode mode, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '时区',
                style: TextStyle(
                  fontSize: 13,
                  color: context.appColors.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppTime.description(mode),
                style: TextStyle(
                  fontSize: 11,
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: context.appColors.border,
            ),
          ),
          child: DropdownButton<AppTimeZoneMode>(
            value: mode,
            underline: Container(),
            isDense: true,
            style: TextStyle(
              fontSize: 13,
              color: context.appColors.text,
            ),
            dropdownColor: context.appColors.surface,
            items: AppTimeZoneMode.values.map((option) {
              return DropdownMenuItem(
                value: option,
                child: Text(
                    '${AppTime.label(option)}（${AppTime.offsetLabelForMode(option)}）'),
              );
            }).toList(),
            onChanged: (value) async {
              if (value == null) return;
              try {
                await ref.read(timeZoneProvider.notifier).setMode(value);
                final allTasks = await _loadAllTaskItems();
                await ReminderService.refreshAll(allTasks);
                await CalendarService.refreshAll(allTasks);
                _showSnackBar('时区已切换为 ${AppTime.label(value)}');
              } catch (e) {
                _showSnackBar('时区切换失败: $e', isError: true);
              }
            },
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
              color: context.appColors.text,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: context.appColors.border,
            ),
          ),
          child: DropdownButton<String>(
            value: value,
            underline: Container(),
            isDense: true,
            style: TextStyle(
              fontSize: 13,
              color: context.appColors.text,
            ),
            dropdownColor: context.appColors.surface,
            items: options
                .map((opt) => DropdownMenuItem(
                      value: opt['value'],
                      child: Text(opt['label']!),
                    ))
                .toList(),
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
    bool isPassword = false,
    VoidCallback? onPasswordVisibilityToggle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: context.appColors.text,
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
              : (onSubmitted != null
                  ? TextInputAction.go
                  : TextInputAction.done),
          style: TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            suffixIcon: isPassword
                ? InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: onPasswordVisibilityToggle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(
                        obscureText ? AppIcons.hidden : AppIcons.visible,
                        size: 16,
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  )
                : null,
            suffixIconConstraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
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
            color: context.appColors.text,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                color: context.appColors.textSecondary,
              ),
            ),
            ...placeholderHints.map((p) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.appColors.surface,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${p['key']}（${p['desc']}）',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: context.appColors.textSecondary,
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

  /// 构建一个按钮行，包含两个平分的按钮
  Widget _buildButtonRow(List<Widget> children) {
    return Row(
      children: children.map((child) {
        if (child is _SettingButton) {
          return Expanded(
              child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: child,
          ));
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
        backgroundColor: isError ? Colors.red : context.appColors.success,
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
      String passwordToUse = _syncPasswordController.text;
      if (passwordToUse == SyncService.fakePassword) {
        final realPassword = SyncService.realPassword;
        if (realPassword.isNotEmpty) {
          passwordToUse = realPassword;
        }
      }

      await SyncService.setServerUrl(_syncServerUrlController.text);
      final result = await SyncService.register(
        username: _syncUsernameController.text,
        password: passwordToUse,
      );

      if (result.success) {
        setState(() {
          _isLoggedIn = true;
          _syncStatus = '注册成功，正在同步...';
          _syncUsernameController.text = SyncService.username;
          _syncPasswordController.text = SyncService.fakePassword;
        });
        SyncService.startAutoSync();
        _showSnackBar('注册成功');
        _handleSyncNow();
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
      String passwordToUse = _syncPasswordController.text;
      if (passwordToUse == SyncService.fakePassword) {
        final realPassword = SyncService.realPassword;
        if (realPassword.isNotEmpty) {
          passwordToUse = realPassword;
        }
      }

      await SyncService.setServerUrl(_syncServerUrlController.text);
      final result = await SyncService.login(
        username: _syncUsernameController.text,
        password: passwordToUse,
      );

      if (result.success) {
        setState(() {
          _isLoggedIn = true;
          _syncStatus = '登录成功，正在同步...';
          _syncUsernameController.text = SyncService.username;
          _syncPasswordController.text = SyncService.fakePassword;
        });
        SyncService.startAutoSync();
        _showSnackBar('登录成功');
        _handleSyncNow();
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
      SyncService.stopAutoSync();
      await SyncService.logout();
      setState(() {
        _isLoggedIn = false;
        _syncStatus = '已登出';
        _syncUsernameController.clear();
        _syncPasswordController.clear();
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
      final taskNotifier = ref.read(taskProvider.notifier);
      final result = await taskNotifier.sync();

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
      _syncStatus =
          'DB:${info['dbOpen']} lists:${info['lists']} tasks:${info['tasks']} sessions:${info['sessions']}';
    });
    _clearStatusAfterDelay(5000);
  }

  Future<void> _handleTestDownload() async {
    setState(() => _syncStatus = '测试下载中...');
    try {
      final result = await AppDatabase.runDownloadTest();
      ref.read(taskProvider.notifier).loadTasks();
      setState(() {
        _syncStatus =
            '测试完成: lists=${result['listsCount']} tasks=${result['tasksCount']}';
      });
    } catch (e) {
      setState(() => _syncStatus = '测试失败: $e');
    }
    _clearStatusAfterDelay();
  }

  Future<void> _handleExport() async {
    try {
      String? outputPath;
      if (Platform.isMacOS || Platform.isWindows) {
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: '导出数据库备份',
          fileName: 'focus_my_time_backup.db',
          type: FileType.any,
        );
      } else {
        // Mobile platform: choose directory
        final directoryPath = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择保存备份的目录',
        );
        if (directoryPath != null) {
          outputPath = '$directoryPath/focus_my_time_backup.db';
        }
      }

      if (outputPath == null) {
        return; // User canceled
      }

      // Ensure extension is .db
      if (!outputPath.endsWith('.db')) {
        outputPath += '.db';
      }

      await AppDatabase.exportDatabase(outputPath);
      await _loadDbPath();
      _showSnackBar('备份导出成功！');
    } catch (e) {
      _showSnackBar('导出失败: $e', isError: true);
    }
  }

  Future<void> _handleImport() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('导入恢复'),
        content: const Text('导入备份将覆盖当前的所有数据，且无法撤销！确定要继续吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(c).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('确定导入', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择要导入的数据库备份文件 (.db)',
        type: FileType.any,
      );

      if (result == null || result.files.single.path == null) {
        return;
      }

      final backupPath = result.files.single.path!;
      if (!backupPath.endsWith('.db') && !backupPath.endsWith('.sqlite')) {
        _showSnackBar('请选择有效的数据库备份文件 (.db)', isError: true);
        return;
      }

      await AppDatabase.importDatabase(backupPath);

      // Re-initialize lists and tasks
      await ref.read(taskProvider.notifier).loadLists();
      await ref.read(taskProvider.notifier).loadTasks();
      final allTasks = await _loadAllTaskItems();
      await ReminderService.refreshAll(allTasks);
      await CalendarService.refreshAll(allTasks);
      await _loadPermissions();
      await _loadCalendarStatus();

      _showSnackBar('数据库恢复成功！');
    } catch (e) {
      _showSnackBar('导入失败: $e', isError: true);
    }
  }

  Future<List<TaskItem>> _loadAllTaskItems() async {
    final allDbTasks = await AppDatabase.getAllTasks();
    return allDbTasks
        .map((m) => TaskItem(
              id: m['id'] as String,
              listId: m['listId'] as String,
              title: m['title'] as String,
              notes: m['notes'] as String?,
              completed: m['completed'] == true,
              completedAt: m['completedAt'] as int?,
              dueDate: m['dueDate'] as String?,
              dueTime: m['dueTime'] as String?,
              sortOrder: m['sortOrder'] as int,
              isMyDay: m['isMyDay'] == true,
              myDayAddedAt: m['myDayAddedAt'] as int?,
              recurrenceConfig: m['recurrenceConfig'] as Map<String, dynamic>?,
              expectedMinutes: m['expectedMinutes'] as int?,
              isImportant: m['isImportant'] == true,
              reminderAt: m['reminderAt'] as int?,
              calendarEventId: m['calendarEventId'] as String?,
              createdAt: m['createdAt'] as int,
              updatedAt: m['updatedAt'] as int,
            ))
        .toList();
  }

  Future<void> _handleCheckForUpdates() async {
    _showSnackBar('正在检查更新...');
    try {
      final updateInfo = await UpdateService.checkForUpdates(force: true);
      if (!mounted) return;
      if (updateInfo == null) {
        _showSnackBar('当前已是最新版本');
        return;
      }
      await UpdateDialog.show(context, updateInfo);
    } catch (e) {
      _showSnackBar('检查更新失败: $e', isError: true);
    }
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
            ? (context.appColors.accentSecondary)
            : isPrimary
                ? (context.appColors.accent)
                : Colors.transparent;

    final textColor = isPrimary || isAccent || isDanger
        ? Colors.white
        : context.appColors.text;

    final borderColor = isDanger
        ? Colors.red
        : isPrimary || isAccent
            ? bgColor
            : context.appColors.border;

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
