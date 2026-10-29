import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../models/detection.dart';

class YoloDetector {
  Interpreter? _interpreter;
  final Map<int, String> _englishLabels = {};
  final Map<int, String> _vietnameseLabels = {};

  // Hằng số lượng tử hóa mô hình YOLO11n INT8
  static const double boxScale = 3.2448902130126953;
  static const int boxZeroPoint = 29;
  static const double scoreScale = 0.00390625; // 1.0 / 256.0
  static const int inputSize = 640;

  // Pre-allocated buffers để tránh cấp phát bộ nhớ & GC lag trên từng khung hình
  late List<List<List<List<int>>>> _inputTensor;
  late List<List<List<int>>> _boxesOut;
  late List<List<int>> _scoresOut;
  late List<List<int>> _classesOut;
  late Map<int, Object> _outputsMap;

  bool get isReady => _interpreter != null;

  Future<void> init() async {
    try {
      // 1. Nạp nhãn tiếng Việt
      final labelsData = await rootBundle.loadString('assets/models/labels_vn.txt');
      for (final line in labelsData.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final parts = trimmed.split(':');
        if (parts.length >= 3) {
          final id = int.tryParse(parts[0]) ?? -1;
          if (id >= 0) {
            _englishLabels[id] = parts[1];
            _vietnameseLabels[id] = parts[2];
          }
        }
      }

      // 2. Chuẩn bị trước các buffer tái sử dụng
      _inputTensor = List.generate(
        1,
        (_) => List.generate(
          inputSize,
          (_) => List.generate(inputSize, (_) => List.filled(3, 0)),
        ),
      );
      _boxesOut = List.generate(1, (_) => List.generate(8400, (_) => List<int>.filled(4, 0)));
      _scoresOut = List.generate(1, (_) => List<int>.filled(8400, 0));
      _classesOut = List.generate(1, (_) => List<int>.filled(8400, 0));
      _outputsMap = {
        0: _boxesOut,
        1: _scoresOut,
        2: _classesOut,
      };

      // 3. Khởi tạo Interpreter với 4 CPU threads
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset('assets/models/yolo11n.tflite', options: options);
    } catch (_) {}
  }

  /// Xử lý trực tiếp từ CameraImage với SIMD-like integer YUV to RGB & xoay 90 độ chuẩn xác (Đạt 20-30 FPS)
  List<Detection> detectFromCameraImage(
    CameraImage image, {
    int sensorOrientation = 90,
    double confThreshold = 0.35,
    double iouThreshold = 0.45,
  }) {
    if (_interpreter == null) return [];

    final planeY = image.planes[0].bytes;
    final planeU = image.planes[1].bytes;
    final planeV = image.planes[2].bytes;

    final int yRowStride = image.planes[0].bytesPerRow;
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    final int srcWidth = image.width;
    final int srcHeight = image.height;

    final tensorPixels = _inputTensor[0];

    // Chuyển đổi và xoay đúng chiều chỉ trong 1 vòng lặp duy nhất
    if (sensorOrientation == 90) {
      for (int yOut = 0; yOut < inputSize; yOut++) {
        final int srcX = (yOut * (srcWidth - 1)) ~/ inputSize;
        final row = tensorPixels[yOut];

        for (int xOut = 0; xOut < inputSize; xOut++) {
          final int srcY = ((inputSize - 1 - xOut) * (srcHeight - 1)) ~/ inputSize;

          final int yIndex = srcY * yRowStride + srcX;
          final int uvIndex = (srcY >> 1) * uvRowStride + (srcX >> 1) * uvPixelStride;

          final int yp = planeY[yIndex];
          final int up = planeU[uvIndex];
          final int vp = planeV[uvIndex];

          final int r = (yp + ((351 * (vp - 128)) >> 8)).clamp(0, 255);
          final int g = (yp - ((86 * (up - 128) + 179 * (vp - 128)) >> 8)).clamp(0, 255);
          final int b = (yp + ((443 * (up - 128)) >> 8)).clamp(0, 255);

          final rgb = row[xOut];
          rgb[0] = r;
          rgb[1] = g;
          rgb[2] = b;
        }
      }
    } else {
      for (int yOut = 0; yOut < inputSize; yOut++) {
        final int srcY = (yOut * (srcHeight - 1)) ~/ inputSize;
        final row = tensorPixels[yOut];

        for (int xOut = 0; xOut < inputSize; xOut++) {
          final int srcX = (xOut * (srcWidth - 1)) ~/ inputSize;

          final int yIndex = srcY * yRowStride + srcX;
          final int uvIndex = (srcY >> 1) * uvRowStride + (srcX >> 1) * uvPixelStride;

          final int yp = planeY[yIndex];
          final int up = planeU[uvIndex];
          final int vp = planeV[uvIndex];

          final int r = (yp + ((351 * (vp - 128)) >> 8)).clamp(0, 255);
          final int g = (yp - ((86 * (up - 128) + 179 * (vp - 128)) >> 8)).clamp(0, 255);
          final int b = (yp + ((443 * (up - 128)) >> 8)).clamp(0, 255);

          final rgb = row[xOut];
          rgb[0] = r;
          rgb[1] = g;
          rgb[2] = b;
        }
      }
    }

    _interpreter!.runForMultipleInputs([_inputTensor], _outputsMap);
    return _parseOutput(confThreshold, iouThreshold);
  }

  /// Xử lý từ ảnh tĩnh hoặc khung hình trích xuất từ Video
  List<Detection> detectFromImage(
    img.Image inputImage, {
    double confThreshold = 0.35,
    double iouThreshold = 0.45,
  }) {
    if (_interpreter == null) return [];

    final resized = img.copyResize(inputImage, width: inputSize, height: inputSize);
    final tensorPixels = _inputTensor[0];

    for (int y = 0; y < inputSize; y++) {
      final row = tensorPixels[y];
      for (int x = 0; x < inputSize; x++) {
        final pixel = resized.getPixel(x, y);
        final rgb = row[x];
        rgb[0] = pixel.r.toInt();
        rgb[1] = pixel.g.toInt();
        rgb[2] = pixel.b.toInt();
      }
    }

    _interpreter!.runForMultipleInputs([_inputTensor], _outputsMap);
    return _parseOutput(confThreshold, iouThreshold);
  }

  List<Detection> _parseOutput(double confThreshold, double iouThreshold) {
    final rawBoxes = _boxesOut[0];
    final rawScores = _scoresOut[0];
    final rawClasses = _classesOut[0];

    final List<Detection> candidates = [];

    for (int i = 0; i < 8400; i++) {
      final double score = rawScores[i] * scoreScale;
      if (score >= confThreshold) {
        final box = rawBoxes[i];
        final double x1 = (box[0] - boxZeroPoint) * boxScale;
        final double y1 = (box[1] - boxZeroPoint) * boxScale;
        final double x2 = (box[2] - boxZeroPoint) * boxScale;
        final double y2 = (box[3] - boxZeroPoint) * boxScale;

        final double left = (x1 / inputSize).clamp(0.0, 1.0);
        final double top = (y1 / inputSize).clamp(0.0, 1.0);
        final double right = (x2 / inputSize).clamp(0.0, 1.0);
        final double bottom = (y2 / inputSize).clamp(0.0, 1.0);

        if (right > left && bottom > top) {
          final int classId = rawClasses[i];
          candidates.add(Detection(
            box: Rect.fromLTRB(left, top, right, bottom),
            classId: classId,
            label: _englishLabels[classId] ?? 'Class $classId',
            vietnameseLabel: _vietnameseLabels[classId] ?? (_englishLabels[classId] ?? 'Vật thể'),
            score: score,
          ));
        }
      }
    }

    return _applyNMS(candidates, iouThreshold);
  }

  List<Detection> _applyNMS(List<Detection> boxes, double iouThreshold) {
    boxes.sort((a, b) => b.score.compareTo(a.score));
    final List<Detection> result = [];

    for (final box in boxes) {
      bool shouldSelect = true;
      for (final selected in result) {
        if (box.classId == selected.classId) {
          final iou = _calculateIoU(box.box, selected.box);
          if (iou > iouThreshold) {
            shouldSelect = false;
            break;
          }
        }
      }
      if (shouldSelect) {
        result.add(box);
      }
    }
    return result;
  }

  double _calculateIoU(Rect a, Rect b) {
    final intersection = a.intersect(b);
    if (intersection.width <= 0 || intersection.height <= 0) return 0.0;
    final intersectionArea = intersection.width * intersection.height;
    final unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea;
    return unionArea > 0 ? (intersectionArea / unionArea) : 0.0;
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
  }
}
