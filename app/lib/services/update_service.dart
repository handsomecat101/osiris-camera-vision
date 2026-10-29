import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final int versionCode;
  final String releaseNotes;
  final String downloadUrl;
  final int fileSize;

  UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileSize,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final android = json['android'] as Map<String, dynamic>? ?? {};
    return UpdateInfo(
      version: json['version']?.toString() ?? '1.0.0',
      versionCode: int.tryParse(json['versionCode']?.toString() ?? '') ?? 1,
      releaseNotes: json['releaseNotes']?.toString() ?? 'Cập nhật tính năng & sửa lỗi hiệu năng.',
      downloadUrl: android['downloadUrl']?.toString() ??
          'https://vision.jimmyvu.me/dl/OsirisCameraVision-release.apk',
      fileSize: int.tryParse(android['fileSize']?.toString() ?? '') ?? 78198043,
    );
  }
}

class UpdateService {
  static const MethodChannel _installerChannel =
      MethodChannel('com.osiris.cameravision/installer');

  static const String manifestUrl = 'https://vision.jimmyvu.me/version.json';

  static String currentVersionName = '1.0.0';
  static int currentVersionCode = 1;
  static bool _hasLoadedNative = false;

  /// Đọc chính xác version cài đặt từ Android PackageManager qua MethodChannel
  static Future<void> loadNativeVersion() async {
    if (!Platform.isAndroid || _hasLoadedNative) return;
    try {
      final Map<dynamic, dynamic>? info =
          await _installerChannel.invokeMethod('getAppVersion');
      if (info != null) {
        if (info['versionName'] != null) {
          currentVersionName = info['versionName'].toString();
        }
        if (info['versionCode'] != null) {
          currentVersionCode =
              int.tryParse(info['versionCode'].toString()) ?? currentVersionCode;
        }
        _hasLoadedNative = true;
        debugPrint('Loaded native version: v$currentVersionName (code $currentVersionCode)');
      }
    } catch (e) {
      debugPrint('Error loading native version: $e');
    }
  }

  /// Tự động kiểm tra bản cập nhật mới nhất trên Cloudflare Edge
  static Future<UpdateInfo?> checkForUpdate() async {
    await loadNativeVersion();
    try {
      final url = Uri.parse('$manifestUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final response = await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final info = UpdateInfo.fromJson(data);

        if (_isNewer(info.version, info.versionCode, currentVersionName, currentVersionCode)) {
          return info;
        }
      }
    } catch (e) {
      debugPrint('Check update error: $e');
    }
    return null;
  }

  static bool _isNewer(String latest, int latestCode, String current, int currentCode) {
    if (latestCode > currentCode) return true;
    try {
      final lParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      for (int i = 0; i < 3; i++) {
        final l = i < lParts.length ? lParts[i] : 0;
        final c = i < cParts.length ? cParts[i] : 0;
        if (l > c) return true;
        if (l < c) return false;
      }
    } catch (_) {}
    return false;
  }

  /// Tải APK tốc độ cao chuẩn Lumina Pipeline với Resume Range và Throttling
  static Future<String> downloadAndInstallApk({
    required String url,
    required Function(int receivedBytes, int totalBytes, String speedText) onProgress,
  }) async {
    await loadNativeVersion();

    final tempDir = await getTemporaryDirectory();
    final apkFile = File('${tempDir.path}/OsirisCameraVision-update.apk');
    final partFile = File('${apkFile.path}.download');

    int receivedBytes = 0;
    int totalBytes = 0;

    // 1. Kiểm tra kích thước file qua HEAD request trước
    try {
      final headRes = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (headRes.statusCode == 200 || headRes.statusCode == 206) {
        final cl = headRes.headers['content-length'];
        if (cl != null) totalBytes = int.tryParse(cl) ?? 0;
      }
    } catch (_) {}

    if (totalBytes > 0 && await apkFile.exists()) {
      if (await apkFile.length() == totalBytes) {
        onProgress(totalBytes, totalBytes, '100%');
        return await triggerInstall(apkFile.path);
      } else {
        await apkFile.delete();
      }
    }

    // 2. Kiểm tra partial download để resume
    if (await partFile.exists()) {
      final partLen = await partFile.length();
      if (totalBytes > 0 && partLen < totalBytes) {
        receivedBytes = partLen;
      } else {
        await partFile.delete();
      }
    }

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        final client = http.Client();
        final request = http.Request('GET', Uri.parse(url));

        if (receivedBytes > 0) {
          request.headers['Range'] = 'bytes=$receivedBytes-';
        }

        final response = await client.send(request);

        if (response.statusCode != 200 && response.statusCode != 206) {
          client.close();
          throw Exception('HTTP ${response.statusCode}');
        }

        if (response.statusCode == 200 && receivedBytes > 0) {
          if (await partFile.exists()) await partFile.delete();
          receivedBytes = 0;
        }

        if (totalBytes == 0) {
          final cl = response.headers['content-length'];
          if (cl != null) totalBytes = (int.tryParse(cl) ?? 0) + receivedBytes;
        }

        final sink = partFile.openWrite(
          mode: receivedBytes > 0 ? FileMode.append : FileMode.write,
        );

        DateTime lastUpdate = DateTime.now();
        int lastBytes = receivedBytes;

        await for (final chunk in response.stream) {
          sink.add(chunk);
          receivedBytes += chunk.length;

          final now = DateTime.now();
          final timeDelta = now.difference(lastUpdate).inMilliseconds;
          final bytesDelta = receivedBytes - lastBytes;

          // THROTTLE UI: Chỉ cập nhật khi qua 150ms hoặc đã tải thêm 512KB
          // Triệt tiêu hoàn toàn nghẽn UI loop và TCP backpressure!
          if (timeDelta >= 150 || bytesDelta >= 512 * 1024 || (totalBytes > 0 && receivedBytes >= totalBytes)) {
            final double speedMBs = timeDelta > 0 ? (bytesDelta / (1024 * 1024)) / (timeDelta / 1000.0) : 0;
            final speedText = '${speedMBs.toStringAsFixed(1)} MB/s';

            lastUpdate = now;
            lastBytes = receivedBytes;
            onProgress(receivedBytes, totalBytes, speedText);
          }
        }

        await sink.flush();
        await sink.close();
        client.close();

        if (totalBytes > 0 && receivedBytes < totalBytes) {
          throw Exception('Incomplete stream');
        }

        // Hoàn tất tải: đổi tên atomically
        if (await apkFile.exists()) await apkFile.delete();
        await partFile.rename(apkFile.path);

        onProgress(totalBytes, totalBytes, 'Xong');
        return await triggerInstall(apkFile.path);
      } catch (e) {
        retryCount++;
        debugPrint('Download error ($retryCount/$maxRetries): $e');
        if (retryCount >= maxRetries) {
          return 'DOWNLOAD_ERROR: $e';
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    return 'UNKNOWN_ERROR';
  }

  /// Gọi MethodChannel khởi chạy PackageInstaller của Android
  static Future<String> triggerInstall(String filePath) async {
    if (Platform.isAndroid) {
      try {
        final String? res = await _installerChannel.invokeMethod<String>(
          'installApk',
          {'filePath': filePath},
        );
        if (res != null && res.isNotEmpty) {
          return res;
        }
      } catch (e) {
        debugPrint('Native installer channel error: $e');
      }
    }

    try {
      final openRes = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      return openRes.type == ResultType.done ? 'SUCCESS' : 'FAILED';
    } catch (_) {
      return 'FAILED';
    }
  }

  /// Kiểm tra quyền cài đặt ứng dụng từ nguồn ngoài
  static Future<bool> canRequestPackageInstalls() async {
    if (!Platform.isAndroid) return true;
    try {
      final bool? result =
          await _installerChannel.invokeMethod<bool>('canRequestPackageInstalls');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Mở màn hình cài đặt cấp quyền của Android
  static Future<void> openInstallPermissionSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _installerChannel.invokeMethod('openInstallPermissionSettings');
    } catch (_) {}
  }
}
