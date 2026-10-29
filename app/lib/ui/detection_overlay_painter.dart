import 'package:flutter/material.dart';
import '../models/detection.dart';

class DetectionOverlayPainter extends CustomPainter {
  final List<Detection> detections;
  final List<Offset> roiPolygon;
  final bool isRoiViolated;

  DetectionOverlayPainter({
    required this.detections,
    required this.roiPolygon,
    required this.isRoiViolated,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Vẽ vùng ROI cảnh báo do người dùng vẽ tay trên màn hình
    if (roiPolygon.length >= 2) {
      final polyPaint = Paint()
        ..color = isRoiViolated
            ? Colors.red.withOpacity(0.4)
            : Colors.amber.withOpacity(0.25)
        ..style = PaintingStyle.fill;

      final polyBorder = Paint()
        ..color = isRoiViolated ? Colors.redAccent : Colors.amberAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      final path = Path();
      path.moveTo(roiPolygon[0].dx * size.width, roiPolygon[0].dy * size.height);
      for (int i = 1; i < roiPolygon.length; i++) {
        path.lineTo(roiPolygon[i].dx * size.width, roiPolygon[i].dy * size.height);
      }
      if (roiPolygon.length > 2) {
        path.close();
        canvas.drawPath(path, polyPaint);
      }
      canvas.drawPath(path, polyBorder);
    }

    // 2. Vẽ Bounding Box & Nhãn Tiếng Việt mượt mà
    for (final det in detections) {
      final rect = Rect.fromLTRB(
        det.box.left * size.width,
        det.box.top * size.height,
        det.box.right * size.width,
        det.box.bottom * size.height,
      );

      final color = _getColorForClass(det.classId);

      final boxPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      canvas.drawRRect(rrect, boxPaint);

      // Nhãn thông tin
      final labelText = '${det.vietnameseLabel} ${(det.score * 100).toInt()}%';
      final textSpan = TextSpan(
        text: labelText,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final labelBgRect = Rect.fromLTWH(
        rect.left,
        max(0, rect.top - textPainter.height - 4),
        textPainter.width + 10,
        textPainter.height + 4,
      );

      final bgPaint = Paint()..color = color.withOpacity(0.85);
      canvas.drawRRect(RRect.fromRectAndRadius(labelBgRect, const Radius.circular(4)), bgPaint);
      textPainter.paint(canvas, Offset(labelBgRect.left + 5, labelBgRect.top + 2));
    }
  }

  Color _getColorForClass(int classId) {
    if (classId == 0) return Colors.greenAccent; // Người
    if ([1, 2, 3, 5, 7].contains(classId)) return Colors.cyanAccent; // Xe
    if ([14, 15, 16].contains(classId)) return Colors.orangeAccent; // Thú cưng
    return Colors.purpleAccent; // Đồ dùng & vật thể khác
  }

  double max(double a, double b) => a > b ? a : b;

  @override
  bool shouldRepaint(covariant DetectionOverlayPainter oldDelegate) => true;
}
