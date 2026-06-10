import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:focus_my_time/core/theme/app_icons.dart';
import 'package:focus_my_time/core/theme/app_theme.dart';
import 'package:focus_my_time/core/utils/app_time.dart';
import 'package:focus_my_time/data/database/app_database.dart';
import 'package:focus_my_time/features/tasks/providers/task_provider.dart';

class ArchivedItemsDialog extends ConsumerStatefulWidget {
  const ArchivedItemsDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const ArchivedItemsDialog(),
    );
  }

  @override
  ConsumerState<ArchivedItemsDialog> createState() =>
      _ArchivedItemsDialogState();
}

class _ArchivedItemsDialogState extends ConsumerState<ArchivedItemsDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _archivedLists = [];
  List<Map<String, dynamic>> _archivedTasks = [];

  @override
  void initState() {
    super.initState();
    _loadArchivedItems();
  }

  Future<void> _loadArchivedItems() async {
    setState(() => _isLoading = true);
    try {
      final lists = await AppDatabase.getArchivedLists();
      final tasks = await AppDatabase.getArchivedTasks();
      if (!mounted) return;
      setState(() {
        _archivedLists = lists;
        _archivedTasks = tasks;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('读取归档失败: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.appColors.surface,
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 12, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      title: Row(
        children: [
          AppIcon(
            AppIcons.archive,
            size: AppIconSizes.nav,
            color: context.appColors.text,
          ),
          const SizedBox(width: AppIconSpacing.compactGap),
          Text(
            '归档管理',
            style: TextStyle(fontSize: 18, color: context.appColors.text),
          ),
          const Spacer(),
          IconButton(
            tooltip: '刷新',
            onPressed: _loadArchivedItems,
            icon: const Icon(AppIcons.reset),
          ),
        ],
      ),
      content: SizedBox(
        width: 720,
        height: 520,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildContent(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_archivedLists.isEmpty && _archivedTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              AppIcons.archive,
              size: AppIconSizes.empty,
              color: context.appColors.textSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              '还没有归档内容',
              style: TextStyle(
                fontSize: 15,
                color: context.appColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        _buildSectionHeader(
          title: '归档清单',
          subtitle: '恢复清单会同时恢复其中的任务',
          count: _archivedLists.length,
        ),
        if (_archivedLists.isEmpty)
          _buildEmptyLine('暂无归档清单')
        else
          ..._archivedLists.map(_buildArchivedListTile),
        const SizedBox(height: 18),
        _buildSectionHeader(
          title: '单独归档的任务',
          subtitle: '不包含已经随清单一起归档的任务',
          count: _archivedTasks.length,
        ),
        if (_archivedTasks.isEmpty)
          _buildEmptyLine('暂无单独归档的任务')
        else
          ..._archivedTasks.map(_buildArchivedTaskTile),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title ($count)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.appColors.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchivedListTile(Map<String, dynamic> list) {
    final name = list['name'] as String;
    final taskCount = list['taskCount'] as int? ?? 0;
    return _ArchiveTile(
      icon: AppIcons.list,
      title: name,
      subtitle:
          '$taskCount 个任务 · ${_formatArchivedAt(list['archivedAt'] as int?)}',
      onRestore: () => _restoreList(list['id'] as String),
      onDelete: () => _confirmDeleteList(list),
    );
  }

  Widget _buildArchivedTaskTile(Map<String, dynamic> task) {
    final listName = task['listName'] as String? ?? '原清单不可用';
    final dueDate = task['dueDate'] as String?;
    final dueText = dueDate == null ? '' : ' · 截止 $dueDate';
    return _ArchiveTile(
      icon: AppIcons.tasks,
      title: task['title'] as String,
      subtitle:
          '$listName$dueText · ${_formatArchivedAt(task['archivedAt'] as int?)}',
      isCompleted: task['completed'] == true,
      onRestore: () => _restoreTask(task['id'] as String),
      onDelete: () => _confirmDeleteTask(task),
    );
  }

  Widget _buildEmptyLine(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: context.appColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appColors.border),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: context.appColors.textSecondary),
      ),
    );
  }

  String _formatArchivedAt(int? timestamp) {
    if (timestamp == null) return '归档时间未知';
    final date = AppTime.fromMillisecondsSinceEpoch(timestamp);
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final mm = date.minute.toString().padLeft(2, '0');
    return '归档于 $y-$m-$d $hh:$mm';
  }

  Future<void> _restoreList(String id) async {
    try {
      await ref.read(taskProvider.notifier).restoreArchivedList(id);
      await _loadArchivedItems();
      _showSnackBar('清单已恢复');
    } catch (e) {
      _showSnackBar('恢复清单失败: $e', isError: true);
    }
  }

  Future<void> _restoreTask(String id) async {
    try {
      await ref.read(taskProvider.notifier).restoreArchivedTask(id);
      await _loadArchivedItems();
      _showSnackBar('任务已恢复');
    } catch (e) {
      _showSnackBar('恢复任务失败: $e', isError: true);
    }
  }

  Future<void> _confirmDeleteList(Map<String, dynamic> list) async {
    final confirmed = await _confirmDelete(
      title: '删除归档清单',
      message: '确定要删除 "${list['name']}" 吗？其中的归档任务也会被删除，之后无法在应用内恢复。',
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(taskProvider.notifier)
          .deleteArchivedList(list['id'] as String);
      await _loadArchivedItems();
      _showSnackBar('清单已删除');
    } catch (e) {
      _showSnackBar('删除清单失败: $e', isError: true);
    }
  }

  Future<void> _confirmDeleteTask(Map<String, dynamic> task) async {
    final confirmed = await _confirmDelete(
      title: '删除归档任务',
      message: '确定要删除 "${task['title']}" 吗？之后无法在应用内恢复。',
    );
    if (confirmed != true) return;

    try {
      await ref
          .read(taskProvider.notifier)
          .deleteArchivedTask(task['id'] as String);
      await _loadArchivedItems();
      _showSnackBar('任务已删除');
    } catch (e) {
      _showSnackBar('删除任务失败: $e', isError: true);
    }
  }

  Future<bool?> _confirmDelete({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appColors.surface,
        title: Text(title, style: TextStyle(color: context.appColors.text)),
        content: Text(
          message,
          style: TextStyle(color: context.appColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : context.appColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRestore,
    required this.onDelete,
    this.isCompleted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.appColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.appColors.border),
      ),
      child: ListTile(
        dense: true,
        leading: AppIcon(
          icon,
          size: AppIconSizes.nav,
          color: context.appColors.textSecondary,
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: context.appColors.text,
            decoration: isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: context.appColors.textSecondary,
          ),
        ),
        trailing: Wrap(
          spacing: 4,
          children: [
            IconButton(
              tooltip: '恢复',
              onPressed: onRestore,
              icon: const Icon(AppIcons.restore),
            ),
            IconButton(
              tooltip: '删除',
              onPressed: onDelete,
              color: Colors.red,
              icon: const Icon(AppIcons.deleteForever),
            ),
          ],
        ),
      ),
    );
  }
}
