import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/update_service.dart';

class UpdateDialog extends StatelessWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('发现新版本: v${updateInfo.version}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '更新内容:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(updateInfo.releaseNotes),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            // 忽略此版本
            await UpdateService.ignoreVersion(updateInfo.version);
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('忽略此版本', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () {
            // 下次再说
            Navigator.of(context).pop();
          },
          child: const Text('下次再说'),
        ),
        FilledButton(
          onPressed: () async {
            // 立即下载 (浏览器打开)
            final url = Uri.parse(updateInfo.htmlUrl);
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: const Text('立即下载'),
        ),
      ],
    );
  }

  /// 静态方法用于在全局显示更新弹窗
  static Future<void> show(BuildContext context, UpdateInfo updateInfo) {
    return showDialog(
      context: context,
      barrierDismissible: false, // 强制用户做出选择
      builder: (context) => UpdateDialog(updateInfo: updateInfo),
    );
  }
}
