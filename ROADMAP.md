# LỘ TRÌNH PHÁT TRIỂN & NGHIỆM THU — Osiris Camera Vision

> Phiên bản mục tiêu: **v1.0.0 (Android APK Native Release)**

---

## 1. Các Mốc Triển Khai (Milestones)

### Giai đoạn 1: Chuẩn bị Mô hình & Lớp Dữ liệu (Model & Assets Preparation) ✅
- [x] Xuất mô hình `yolo11n.tflite` (~2.8MB) và `yolo11n.onnx` (~10MB) từ dự án tham chiếu `cam-ai`.
- [x] Chuẩn hóa bộ nhãn tiếng Việt `labels_vn.txt` (80 lớp COCO, đồng bộ với `cam_ai_core.py`).
- [x] Nhúng tài nguyên vào thư mục assets của ứng dụng Flutter.

### Giai đoạn 2: Khởi tạo Bộ Khung Ứng Dụng Flutter (Flutter App Foundation) ✅
- [x] Khởi tạo dự án Flutter trong thư mục `app/` (Package name: `com.osiris.cameravision`).
- [x] Tích hợp các plugin nền tảng: `camera`, `video_player`, `tflite_flutter`, `image`, `vibration`, `file_picker`, `open_filex`.
- [x] Cấu hình quyền Android trong `AndroidManifest.xml` (`CAMERA`, `READ_MEDIA_VIDEO`, `VIBRATE`, `REQUEST_INSTALL_PACKAGES`).

### Giai đoạn 3: Tích hợp AI Inference & Live Camera (Realtime Pipeline) ✅
- [x] Viết `yolo_detector.dart` nạp model TFLite tối ưu đa luồng CPU di động.
- [x] Viết `DetectionOverlayPainter` vẽ Bounding Box vector mượt mà trên màn hình xem trực tiếp.
- [x] Bộ lọc chọn nhanh nhóm vật thể (Người, Xe cộ, Thú cưng) kèm đo FPS thời gian thực.

### Giai đoạn 4: Chế độ Xem lại Video & Nguồn ngoài (Video Review Mode) ✅
- [x] Tích hợp bộ chọn video từ máy hoặc nguồn ngoài bằng `file_picker` & `video_player`.
- [x] Chuyển đổi linh hoạt 1 chạm giữa chế độ Camera và Video.

### Giai đoạn 5: Vùng Cảnh Báo Cảm Ứng & Cảnh Báo (Touch ROI & Smart Alert) ✅
- [x] Lớp phủ cảm ứng (`GestureDetector`) cho phép dùng ngón tay vẽ đa giác (Polygon ROI) trên màn hình.
- [x] Chuyển đổi tọa độ vẽ sang hệ chuẩn hóa (0.0 – 1.0) để tương thích với thuật toán kế thừa từ `cam-ai`.
- [x] Kích hoạt rung và cảnh báo tức thì khi có đối tượng xâm nhập vùng cấm.

### Giai đoạn 6: Đóng gói & Phân phối JimmyVu App Launch Stack ✅
- [x] Build thành công file cài đặt `app-release.apk` (74.3MB).
- [x] Tạo R2 bucket `osiris-vision-storage` và Worker `osiris-vision-web`.
- [x] Cấu hình Custom Subdomain `vision.jimmyvu.me` tự động kích hoạt SSL.
- [x] Tích hợp tính năng In-App Self-Update (OTA) qua `version.json`.

---

## 2. Tiêu Chí Nghiệm Thu (Acceptance Criteria)

| # | Hạng mục | Tiêu chí đạt |
|---|---|---|
| **AC1** | **Cài đặt & Khởi động** | Cài đặt được file `.apk` trên Android 10 trở lên, mở app trong vòng < 2 giây. |
| **AC2** | **Quay Realtime** | Luồng camera hiển thị mượt mà, AI quét liên tục và vẽ đúng khung người, xe, đồ vật. |
| **AC3** | **Tốc độ & Nhiệt độ** | Đạt tối thiểu **25 - 45 FPS** trên điện thoại; chạy liên tục 15 phút không văng (crash) app. |
| **AC4** | **Xem lại Video** | Mở được file video bất kỳ trong máy, hiển thị phát hiện vật thể đồng bộ với video. |
| **AC5** | **Vẽ vùng cảm ứng** | Dùng ngón tay khoanh vùng được, hệ thống cảnh báo tức thì khi có đối tượng bước vào vùng. |
| **AC6** | **Offline 100%** | Bật chế độ máy bay (Airplane mode), ứng dụng vẫn chạy đầy đủ tính năng bình thường. |
