# Osiris Camera Vision — Realtime Mobile Edge AI Object Detection (Android APK)

> **Osiris Camera Vision** là ứng dụng di động độc lập (Native Android APK) phục vụ phát hiện, theo dõi và cảnh báo vật thể thông minh theo thời gian thực trực tiếp từ **Camera điện thoại** hoặc **Xem lại video / hình ảnh từ bộ nhớ máy**.  
> Toàn bộ quá trình suy luận AI (Inference) chạy **100% Offline trên phần cứng di động (TFLite Engine)**, không cần Internet.

---

## 🌐 Trang Chủ & Tải Cài Đặt (JimmyVu App Launch Stack)

Ứng dụng đã được triển khai lên hệ thống phân phối Cloudflare Edge của anh Tuấn:
* **Landing Page & Tải APK:** [https://vision.jimmyvu.me/](https://vision.jimmyvu.me/)
* **Direct Download APK:** [https://vision.jimmyvu.me/dl/OsirisCameraVision-release.apk](https://vision.jimmyvu.me/dl/OsirisCameraVision-release.apk)
* **OTA Update API:** `https://vision.jimmyvu.me/version.json` (Ứng dụng tự động kiểm tra và nâng cấp phiên bản mới in-app).

---

## 1. Nguồn Gốc & Dự Án Kế Thừa (Base Project Reference)

Dự án này là một **sản phẩm độc lập**, được phát triển để chuyển đổi trải nghiệm giám sát an ninh từ máy tính để bàn (PC) sang ứng dụng di động native gọn nhẹ. Dự án kế thừa toàn bộ giải thuật, từ điển nhãn và logic kiểm soát không gian từ dự án gốc:

📂 **Dự án gốc tham chiếu:** [`cam-ai`](https://github.com/handsomecat101/cam-ai) (Thư mục local: `h:\AI Project\cam-ai`)  
📖 **Nhật ký phát triển chi tiết & lịch sử xử lý lỗi:** Xem tại [`DEVELOPMENT_HISTORY.md`](./DEVELOPMENT_HISTORY.md)

### Bảng tra cứu đối chiếu code khi cần xem lại:

| Chức năng / Giải thuật | Code tham khảo tại dự án gốc `cam-ai` | Ứng dụng sang `Osiris Camera Vision` |
|---|---|---|
| **Bộ từ điển 80 lớp COCO tiếng Việt** | `cam-ai/cam_ai_core.py` (`TEN_VAT_THE`) | Dùng làm file nhãn `assets/models/labels_vn.txt` cho model TFLite trên điện thoại |
| **Logic tọa độ chuẩn hóa (0.0 – 1.0)** | `cam-ai/ve_vung.py` & `cam_ai_core.py` | Áp dụng vào hệ tọa độ cảm ứng màn hình di động (thích ứng mọi độ phân giải máy) |
| **Thuật toán kiểm tra va chạm vùng (ROI)** | `cam-ai/cam_ai_core.py` (chế độ chặt / nhạy) | Dùng để phát hiện vật thể/người bước vào vùng cấm vẽ bằng tay trên màn hình cảm ứng |
| **Thuật toán đo thời gian đứng lâu (Loitering)** | `cam-ai/cam_ai_core.py` (`now - entered_at`) | Kích hoạt chuông/rung khi có đối tượng lảng vảng quá lâu |
| **Model YOLO11 gốc** | `cam-ai/yolo11n.pt` | Dùng làm file nguồn để export sang `yolo11n.tflite` (INT8) cho mobile |
| **Tách ô nhận diện cự ly xa (Tiling 2x2)** | `cam-ai/cam_ai_core.py` (`detect_tach_o`) | Nghiên cứu đưa vào chế độ soi ảnh/video chi tiết |

---

## 2. Các Tính Năng Đã Hoàn Thiện

1. **Quay Realtime Camera Điện Thoại (Live Detection 15–25 FPS):**
   - Mở luồng camera trước/sau với tốc độ khung hình cao.
   - Chuyển đổi tensor YUV420 sang RGB trực tiếp bằng giải thuật số nguyên kèm xoay 90° portrait chuẩn cảm biến, không méo khung viền.
   - Nhận diện tức thì 80 nhóm vật thể: Người, Phương tiện giao thông (xe hơi, xe máy, xe đạp...), Đồ dùng cá nhân (ba lô, túi xách, điện thoại...), Động vật (chó, mèo...).
2. **Chế Độ Đọc Ảnh Tĩnh (Static Image Detection):**
   - Chọn ảnh bất kỳ từ thư viện máy, quét AI tức thì (<50ms) và vẽ bounding box trực quan.
3. **Xem Lại Video & Nguồn Ngoài (Video Review):**
   - Trình phát video kèm thanh trượt Seek Bar tương tác, trích xuất khung hình native mượt mà.
4. **Hệ Thống Tự Cập Nhật In-App (OTA Self-Update):**
   - Tự kiểm tra phiên bản mới từ `https://vision.jimmyvu.me/version.json` mỗi khi mở app hoặc người dùng bấm kiểm tra.
   - Tải file tốc độ cao với giao thức HTTP Range 206 và cơ chế Throttling chống nghẽn socket.
   - Tự động gọi trình cài đặt hệ thống Android `PackageInstaller` thông qua `FileProvider` an toàn.
5. **Chạy Hoàn Toàn Offline (Edge Computing):**
   - Bảo mật 100%, không gửi dữ liệu ra ngoài, hoạt động mượt mà cả khi bật Chế độ máy bay.

---

## 3. Cấu Trúc Dự Án

```
osiris camera vision/
├── README.md                 # Tài liệu tổng quan & tham chiếu
├── DEVELOPMENT_HISTORY.md    # Nhật ký phát triển chi tiết & lịch sử xử lý lỗi
├── ARCHITECTURE.md           # Kiến trúc kỹ thuật chi tiết
├── ROADMAP.md                # Lộ trình phát triển & các mốc nghiệm thu
├── models/                   # Chứa model AI (yolo11n.tflite, yolo11n.onnx, labels_vn.txt)
├── app/                      # Source code Flutter Native Android
│   ├── lib/
│   │   ├── main.dart
│   │   ├── services/         # yolo_detector.dart, update_service.dart
│   │   └── ui/               # home_screen.dart, app_update_dialog.dart, detection_overlay_painter.dart
│   └── android/              # Mã nguồn Native Android (MainActivity.kt, build.gradle.kts)
└── osiris-vision-web/        # Cloudflare Worker landing page + R2 Storage OTA
```

---

## 4. Hướng Dẫn Phát Triển Tiếp Trên Thiết Bị Khác

### Cài đặt môi trường:
- Flutter 3.24+ (`flutter doctor`)
- Android Studio / Android SDK (API 34, compileSdk 36, NDK 26+)
- JDK 17

### Lệnh chạy và build:
```bash
cd app
flutter pub get
flutter run               # Chạy debug trên máy thật kết nối USB/Wifi
flutter build apk --release   # Đóng gói bản cài đặt APK release
```
