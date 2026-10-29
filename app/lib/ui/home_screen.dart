import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:video_player/video_player.dart';
import 'package:vibration/vibration.dart';

import '../models/detection.dart';
import '../services/update_service.dart';
import '../services/yolo_detector.dart';
import 'app_update_dialog.dart';
import 'detection_overlay_painter.dart';

enum AppMode { camera, image, video }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.osiris.cameravision/installer');

  final YoloDetector _detector = YoloDetector();
  CameraController? _cameraController;
  VideoPlayerController? _videoController;
  Timer? _videoTimer;

  AppMode _currentMode = AppMode.camera;
  String? _currentVideoPath;
  File? _currentImageFile;

  bool _isProcessingFrame = false;
  bool _isDrawingRoi = false;
  bool _isAlertActive = false;

  List<Detection> _detections = [];
  final List<Offset> _roiPolygon = [];
  int _fpsCount = 0;
  int _currentFps = 0;
  DateTime _lastFpsTime = DateTime.now();
  DateTime _lastFrameTime = DateTime.now();

  // Nhóm lọc vật thể: Người (0), Phương tiện (1,2,3,5,7), Đồ dùng, Thú cưng
  bool _filterPerson = true;
  bool _filterVehicles = true;
  bool _filterPets = true;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    await _detector.init();
    await _initCamera();
    _checkOtaUpdate();
  }

  Future<void> _checkOtaUpdate({bool isManual = false}) async {
    final update = await UpdateService.checkForUpdate();
    if (!mounted) return;
    if (update != null) {
      try {
        await _cameraController?.stopImageStream();
      } catch (_) {}

      if (!mounted) return;
      await AppUpdateDialog.show(context, update);

      if (mounted && _currentMode == AppMode.camera && _cameraController != null && _cameraController!.value.isInitialized) {
        try {
          await _cameraController?.startImageStream((image) => _processCameraFrame(image));
        } catch (_) {}
      }
    } else if (isManual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bạn đang sử dụng phiên bản mới nhất (v${UpdateService.currentVersionName}).'),
          backgroundColor: const Color(0xFF0E7490),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      _cameraController!.startImageStream((CameraImage image) {
        _processCameraFrame(image);
      });

      setState(() {});
    } catch (_) {}
  }

  /// Xử lý khung hình Camera trực tiếp với Fast Direct-to-Tensor (15-25 FPS)
  void _processCameraFrame(CameraImage image) {
    if (_currentMode != AppMode.camera || !_detector.isReady || _isProcessingFrame) return;

    final now = DateTime.now();
    // Giữ nhịp tối thiểu 40ms/frame (~20-25 FPS) để không nghẽn luồng UI
    if (now.difference(_lastFrameTime).inMilliseconds < 40) return;
    _lastFrameTime = now;
    _isProcessingFrame = true;

    try {
      final sensorOri = _cameraController?.description.sensorOrientation ?? 90;
      final rawDetections = _detector.detectFromCameraImage(image, sensorOrientation: sensorOri);
      final filtered = _filterDetections(rawDetections);
      _handleDetections(filtered);
    } finally {
      _isProcessingFrame = false;
    }
  }

  /// Trích xuất và phân tích khung hình video tại thời điểm hiện tại
  Future<void> _processVideoCurrentFrame() async {
    if (_currentVideoPath == null || _isProcessingFrame || !_detector.isReady) return;
    _isProcessingFrame = true;

    try {
      final posMs = _videoController?.value.position.inMilliseconds ?? 0;
      final Uint8List? frameBytes = await _nativeChannel.invokeMethod<Uint8List>(
        'getVideoFrame',
        {'filePath': _currentVideoPath, 'timeMs': posMs},
      );

      if (frameBytes != null && frameBytes.isNotEmpty) {
        final decoded = img.decodeJpg(frameBytes);
        if (decoded != null) {
          final rawDetections = _detector.detectFromImage(decoded);
          final filtered = _filterDetections(rawDetections);
          _handleDetections(filtered);
        }
      }
    } catch (_) {
    } finally {
      _isProcessingFrame = false;
    }
  }

  List<Detection> _filterDetections(List<Detection> raw) {
    return raw.where((d) {
      if (d.classId == 0) return _filterPerson;
      if ([1, 2, 3, 5, 7].contains(d.classId)) return _filterVehicles;
      if ([14, 15, 16].contains(d.classId)) return _filterPets;
      return true;
    }).toList();
  }

  void _handleDetections(List<Detection> filtered) {
    bool violated = false;
    if (_roiPolygon.length >= 3) {
      for (final det in filtered) {
        if (det.isInPolygon(_roiPolygon)) {
          violated = true;
          break;
        }
      }
    }

    if (violated && !_isAlertActive) {
      _triggerAlert();
    }

    _fpsCount++;
    final now = DateTime.now();
    if (now.difference(_lastFpsTime).inMilliseconds >= 1000) {
      _currentFps = _fpsCount;
      _fpsCount = 0;
      _lastFpsTime = now;
    }

    if (mounted) {
      setState(() {
        _detections = filtered;
        _isAlertActive = violated;
      });
    }
  }

  Future<void> _triggerAlert() async {
    _isAlertActive = true;
    try {
      final hasVib = await Vibration.hasVibrator();
      if (hasVib) {
        Vibration.vibrate(duration: 400);
      }
    } catch (_) {}
  }

  /// Chế độ 1: Mở Camera trực tiếp
  void _switchToCamera() {
    _videoTimer?.cancel();
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
    _currentVideoPath = null;
    _currentImageFile = null;

    setState(() {
      _currentMode = AppMode.camera;
      _detections.clear();
      _isAlertActive = false;
      _currentFps = 0;
    });

    try {
      _cameraController?.startImageStream((img) => _processCameraFrame(img));
    } catch (_) {}
  }

  /// Chế độ 2: Chọn Ảnh từ máy để phân tích AI ngay lập tức (<50ms)
  Future<void> _pickImageFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);

      try {
        await _cameraController?.stopImageStream();
      } catch (_) {}
      _videoTimer?.cancel();
      _videoController?.pause();
      _videoController?.dispose();
      _videoController = null;
      _currentVideoPath = null;

      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);

      setState(() {
        _currentMode = AppMode.image;
        _currentImageFile = file;
        _currentFps = 0;
      });

      if (decoded != null) {
        final raw = _detector.detectFromImage(decoded);
        final filtered = _filterDetections(raw);
        _handleDetections(filtered);
      }
    }
  }

  /// Chế độ 3: Chọn Video ngoại vi để xem lại và phân tích
  Future<void> _pickVideoFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      _currentVideoPath = file.path;
      _currentImageFile = null;

      try {
        await _cameraController?.stopImageStream();
      } catch (_) {}
      _videoTimer?.cancel();
      _videoController?.dispose();

      _videoController = VideoPlayerController.file(file)
        ..initialize().then((_) {
          setState(() {
            _currentMode = AppMode.video;
            _videoController!.play();
            _videoController!.setLooping(true);
          });
          _startVideoFrameLoop();
          _processVideoCurrentFrame();
        });
    }
  }

  void _startVideoFrameLoop() {
    _videoTimer?.cancel();
    _videoTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_currentMode == AppMode.video &&
          _videoController != null &&
          _videoController!.value.isPlaying &&
          !_isProcessingFrame) {
        _processVideoCurrentFrame();
      }
    });
  }

  @override
  void dispose() {
    _videoTimer?.cancel();
    _cameraController?.dispose();
    _videoController?.dispose();
    _detector.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. Khung hiển thị nội dung chính (Camera / Ảnh / Video)
            Positioned.fill(
              child: Center(
                child: _buildMainContent(),
              ),
            ),

            // 2. Lớp Canvas Bounding Box & ROI đa điểm
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (details) {
                  if (_isDrawingRoi) {
                    setState(() {
                      final box = context.findRenderObject() as RenderBox;
                      final local = box.globalToLocal(details.globalPosition);
                      _roiPolygon.clear();
                      _roiPolygon.add(Offset(local.dx / box.size.width, local.dy / box.size.height));
                    });
                  }
                },
                onPanUpdate: (details) {
                  if (_isDrawingRoi) {
                    setState(() {
                      final box = context.findRenderObject() as RenderBox;
                      final local = box.globalToLocal(details.globalPosition);
                      _roiPolygon.add(Offset(local.dx / box.size.width, local.dy / box.size.height));
                    });
                  }
                },
                child: CustomPaint(
                  painter: DetectionOverlayPainter(
                    detections: _detections,
                    roiPolygon: _roiPolygon,
                    isRoiViolated: _isAlertActive,
                  ),
                ),
              ),
            ),

            // 3. Header hiển thị trạng thái và FPS
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isAlertActive ? Icons.warning_amber_rounded : Icons.radar_rounded,
                      color: _isAlertActive ? Colors.redAccent : Colors.cyanAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isAlertActive ? 'CẢNH BÁO XÂM NHẬP' : 'Osiris Vision',
                      style: TextStyle(
                        color: _isAlertActive ? Colors.redAccent : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (_currentMode == AppMode.camera)
                      Text('FPS: $_currentFps',
                          style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                    if (_currentMode == AppMode.image)
                      const Text('Ảnh Tĩnh', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                    if (_currentMode == AppMode.video)
                      const Text('Video MP4', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: () => _checkOtaUpdate(isManual: true),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.cyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.cyan.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.system_update_rounded, size: 14, color: Colors.cyanAccent),
                            SizedBox(width: 4),
                            Text('OTA', style: TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 4. Thanh điều khiển Video (Nếu đang ở chế độ Video)
            if (_currentMode == AppMode.video && _videoController != null && _videoController!.value.isInitialized)
              Positioned(
                bottom: 120,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _videoController!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          color: Colors.cyanAccent,
                          size: 32,
                        ),
                        onPressed: () {
                          setState(() {
                            if (_videoController!.value.isPlaying) {
                              _videoController!.pause();
                            } else {
                              _videoController!.play();
                            }
                          });
                          _processVideoCurrentFrame();
                        },
                      ),
                      Expanded(
                        child: VideoProgressIndicator(
                          _videoController!,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Colors.cyanAccent,
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 5. Bảng điều khiển cảm ứng bên dưới (Bottom Controls)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Nút chọn nhanh bộ lọc
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Người'),
                        selected: _filterPerson,
                        onSelected: (v) => setState(() => _filterPerson = v),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Xe cộ'),
                        selected: _filterVehicles,
                        onSelected: (v) => setState(() => _filterVehicles = v),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('Thú cưng'),
                        selected: _filterPets,
                        onSelected: (v) => setState(() => _filterPets = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Thanh chuyển đổi 3 chế độ: Camera • Đọc Ảnh • Xem Video
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2E),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Nút Camera Realtime
                        _buildModeButton(
                          title: 'Camera',
                          icon: Icons.camera_alt_rounded,
                          isActive: _currentMode == AppMode.camera,
                          onTap: _switchToCamera,
                        ),

                        // Nút Đọc Ảnh
                        _buildModeButton(
                          title: 'Đọc Ảnh',
                          icon: Icons.image_rounded,
                          isActive: _currentMode == AppMode.image,
                          onTap: _pickImageFile,
                        ),

                        // Nút Xem Video
                        _buildModeButton(
                          title: 'Video',
                          icon: Icons.video_collection_rounded,
                          isActive: _currentMode == AppMode.video,
                          onTap: _pickVideoFile,
                        ),

                        const SizedBox(width: 4),

                        // Nút Vẽ ROI
                        IconButton(
                          icon: Icon(_isDrawingRoi ? Icons.check_circle_rounded : Icons.gesture_rounded),
                          color: _isDrawingRoi ? Colors.amberAccent : Colors.white70,
                          tooltip: _isDrawingRoi ? 'Xong vẽ' : 'Vẽ vùng ROI',
                          onPressed: () {
                            setState(() {
                              _isDrawingRoi = !_isDrawingRoi;
                            });
                          },
                        ),

                        // Nút Xóa ROI
                        if (_roiPolygon.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            color: Colors.redAccent,
                            tooltip: 'Xóa vùng',
                            onPressed: () => setState(() => _roiPolygon.clear()),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_currentMode) {
      case AppMode.camera:
        if (_cameraController?.value.isInitialized ?? false) {
          return AspectRatio(
            aspectRatio: 1 / _cameraController!.value.aspectRatio,
            child: CameraPreview(_cameraController!),
          );
        }
        return const Center(child: CircularProgressIndicator(color: Colors.cyanAccent));

      case AppMode.image:
        if (_currentImageFile != null && _currentImageFile!.existsSync()) {
          return Image.file(
            _currentImageFile!,
            fit: BoxFit.contain,
          );
        }
        return const Center(child: Text('Chưa chọn ảnh', style: TextStyle(color: Colors.white60)));

      case AppMode.video:
        if (_videoController?.value.isInitialized ?? false) {
          return AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          );
        }
        return const Center(child: Text('Chưa chọn video', style: TextStyle(color: Colors.white60)));
    }
  }

  Widget _buildModeButton({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.cyan.withValues(alpha: 0.25) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.cyanAccent : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: isActive ? Colors.cyanAccent : Colors.white60),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: isActive ? Colors.cyanAccent : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
