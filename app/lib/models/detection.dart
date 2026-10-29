import 'dart:ui';

class Detection {
  final Rect box; // Tọa độ chuẩn hóa 0.0 - 1.0 (left, top, right, bottom)
  final int classId;
  final String label;
  final String vietnameseLabel;
  final double score;

  Detection({
    required this.box,
    required this.classId,
    required this.label,
    required this.vietnameseLabel,
    required this.score,
  });

  bool isInPolygon(List<Offset> polygon) {
    if (polygon.length < 3) return false;
    final center = Offset(box.center.dx, box.center.dy);
    
    // Thuật toán Ray-Casting kiểm tra điểm nằm trong đa giác (kế thừa từ cam-ai)
    int intersectCount = 0;
    for (int i = 0; i < polygon.length; i++) {
      final p1 = polygon[i];
      final p2 = polygon[(i + 1) % polygon.length];

      if ((p1.dy > center.dy) != (p2.dy > center.dy)) {
        final xIntersect = p1.dx + (center.dy - p1.dy) * (p2.dx - p1.dx) / (p2.dy - p1.dy);
        if (center.dx < xIntersect) {
          intersectCount++;
        }
      }
    }
    return (intersectCount % 2) == 1;
  }
}
