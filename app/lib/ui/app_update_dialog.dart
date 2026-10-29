import 'dart:io';
import 'package:flutter/material.dart';
import '../services/update_service.dart';

enum UpdateState {
  ready,
  needPermission,
  downloading,
  installing,
  error,
}

class AppUpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const AppUpdateDialog({super.key, required this.updateInfo});

  static Future<void> show(BuildContext context, UpdateInfo info) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppUpdateDialog(updateInfo: info),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  UpdateState _state = UpdateState.ready;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String _speedText = '';
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _totalBytes = widget.updateInfo.fileSize;
  }

  Future<void> _startUpdate() async {
    if (Platform.isAndroid) {
      final canInstall = await UpdateService.canRequestPackageInstalls();
      if (!canInstall) {
        setState(() => _state = UpdateState.needPermission);
        return;
      }
    }
    _executeDownload();
  }

  Future<void> _requestPermissionAndProceed() async {
    await UpdateService.openInstallPermissionSettings();
    // Sau khi mở settings, người dùng bật quyền và quay lại app
    setState(() => _state = UpdateState.ready);
  }

  Future<void> _executeDownload() async {
    setState(() {
      _state = UpdateState.downloading;
      _progress = 0.0;
      _receivedBytes = 0;
      _speedText = '';
    });

    final result = await UpdateService.downloadAndInstallApk(
      url: widget.updateInfo.downloadUrl,
      onProgress: (received, total, speed) {
        if (!mounted) return;
        setState(() {
          _receivedBytes = received;
          _totalBytes = total > 0 ? total : _totalBytes;
          _progress = _totalBytes > 0 ? (_receivedBytes / _totalBytes).clamp(0.0, 1.0) : 0.0;
          _speedText = speed;
        });
      },
    );

    if (!mounted) return;

    if (result == 'SUCCESS') {
      setState(() => _state = UpdateState.installing);
      // Đóng dialog sau khi intent đã mở
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) Navigator.of(context).pop();
      });
    } else if (result == 'PERMISSION_REQUESTED') {
      setState(() => _state = UpdateState.needPermission);
    } else {
      setState(() {
        _state = UpdateState.error;
        _errorMessage = result;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.updateInfo;

    return PopScope(
      canPop: _state == UpdateState.ready || _state == UpdateState.error,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF131B2E),
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Colors.cyanAccent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bản Cập Nhật Mới',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'v${UpdateService.currentVersionName}  ➔  v${info.version}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Content based on state
              if (_state == UpdateState.ready) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Có gì mới:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        info.releaseNotes,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white60,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Để sau', style: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyan,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onPressed: _startUpdate,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(
                        'Cập nhật ngay (${_formatBytes(info.fileSize)})',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ] else if (_state == UpdateState.needPermission) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security_rounded, color: Colors.amber, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Yêu cầu quyền cài đặt',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Để ứng dụng tự động cài đặt bản cập nhật trực tiếp mà không cần vào web, vui lòng cấp quyền "Cài đặt ứng dụng không rõ nguồn gốc" cho Osiris Vision.',
                        style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() => _state = UpdateState.ready),
                      child: const Text('Quay lại', style: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _requestPermissionAndProceed,
                      icon: const Icon(Icons.settings_suggest_rounded, size: 18),
                      label: const Text(
                        'Mở cài đặt cấp quyền',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ] else if (_state == UpdateState.downloading) ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 10,
                        backgroundColor: Colors.white12,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_formatBytes(_receivedBytes)} / ${_formatBytes(_totalBytes)}',
                          style: const TextStyle(fontSize: 13, color: Colors.white70),
                        ),
                        Row(
                          children: [
                            if (_speedText.isNotEmpty) ...[
                              Text(
                                _speedText,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              '${(_progress * 100).toInt()}%',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.cyanAccent,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '⚡ Đang tải gói OTA từ Cloudflare Edge...',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ),
              ] else if (_state == UpdateState.installing) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.cyanAccent),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Đang khởi chạy trình cài đặt Android...',
                          style: TextStyle(fontSize: 14, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_state == UpdateState.error) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Lỗi tải bản cập nhật: $_errorMessage',
                    style: const TextStyle(fontSize: 13, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Đóng', style: TextStyle(color: Colors.grey)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _executeDownload,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
