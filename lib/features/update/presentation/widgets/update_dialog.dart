import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:focus_my_time/features/update/services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();

  /// 静态方法用于在全局显示更新弹窗
  static Future<void> show(BuildContext context, UpdateInfo updateInfo) {
    return showDialog(
      context: context,
      barrierDismissible: false, // 强制用户做出选择
      builder: (context) => UpdateDialog(updateInfo: updateInfo),
    );
  }
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isOpeningDownloadPage = false;

  Future<void> _ignoreVersion() async {
    try {
      await UpdateService.ignoreVersion(widget.updateInfo.version);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('忽略版本失败: $e')));
      }
    }
  }

  Future<void> _openDownloadPage() async {
    setState(() {
      _isOpeningDownloadPage = true;
    });

    try {
      final url = Uri.parse(widget.updateInfo.htmlUrl);
      if (!url.hasScheme || !(url.isScheme('http') || url.isScheme('https'))) {
        throw const FormatException('下载链接不是有效的网页地址');
      }

      // Android 11+ 的包可见性可能让 canLaunchUrl 返回 false，
      // 因此这里直接尝试外部浏览器打开，只有成功后才关闭弹窗。
      final launched = await launchUrl(
        url,
        mode: LaunchMode.externalApplication,
      );

      if (!mounted) return;
      if (launched) {
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开浏览器，请稍后重试')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开下载页面: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningDownloadPage = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('发现新版本: v${widget.updateInfo.version}'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('更新内容:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(widget.updateInfo.releaseNotes),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isOpeningDownloadPage ? null : _ignoreVersion,
          child: const Text('忽略此版本', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: _isOpeningDownloadPage
              ? null
              : () {
                  // 下次再说
                  Navigator.of(context).pop();
                },
          child: const Text('下次再说'),
        ),
        FilledButton(
          onPressed: _isOpeningDownloadPage ? null : _openDownloadPage,
          child: _isOpeningDownloadPage
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('立即下载'),
        ),
      ],
    );
  }
}
