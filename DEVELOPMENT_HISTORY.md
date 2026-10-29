# NHẬT KÝ PHÁT TRIỂN & TÀI LIỆU KẾ THỪA (DEVELOPMENT HISTORY & BASE REFERENCES)
# OSIRIS CAMERA VISION — REALTIME MOBILE EDGE AI OBJECT DETECTION (ANDROID)

> **Dự án:** Osiris Camera Vision  
> **Tác giả:** Jimmy Vũ (handsomecat101 / Meodapchai)  
> **Nền tảng mục tiêu:** Android Mobile Native (Flutter 3.24+ / Dart / LiteRT TFLite / CameraX)  
> **Hệ thống phân phối:** Cloudflare Edge Worker + Object Storage R2 + In-App Self-Update (OTA)  
> **Domain công bố:** [https://vision.jimmyvu.me](https://vision.jimmyvu.me)  

---

## 1. NGUỒN GỐC & DỰ ÁN GỐC KẾ THỪA (BASE PROJECT REFERENCE)

Dự án này được khởi tạo và phát triển như một **phiên bản di động độc lập (Mobile Native Spin-off)** lấy cảm hứng và kế thừa toàn bộ triết lý thiết kế, giải thuật thị giác máy tính và từ điển kiểm soát không gian từ dự án giám sát an ninh trên máy tính để bàn (PC Desktop):

* **Dự án gốc tham chiếu:** [`cam-ai`](https://github.com/handsomecat101/cam-ai) (Thư mục local: `h:\AI Project\cam-ai`)
* **Nguyên tắc bất di bất dịch kế thừa:** **Toàn bộ tính năng suy luận AI và xử lý thị giác máy tính chạy 100% Offline trên phần cứng thiết bị (On-Device Edge AI).** Không đẩy luồng video lên cloud hay server trung gian để đảm bảo bảo mật và tốc độ phản hồi tức thì.

### Bảng đối chiếu kiến trúc giữa `cam-ai` (PC) và `Osiris Camera Vision` (Mobile):

| Hạng mục | Dự án gốc `cam-ai` (PC Desktop) | Dự án kế thừa `Osiris Camera Vision` (Android) |
| :--- | :--- | :--- |
| **Hệ điều hành** | Windows Desktop (x86_64) | Android 10.0+ (ARM64-v8a, ARMeabi-v7a) |
| **Ngôn ngữ & Framework** | Python 3.11+, CustomTkinter, OpenCV | Flutter 3.24+, Dart 3.5+, Android Native Kotlin |
| **Model AI & Engine** | YOLO11n PyTorch (`.pt`) & ONNX Runtime (CPU/GPU) | YOLO11n TFLite INT8 Quantized (`.tflite`) qua Google LiteRT C++ |
| **Đầu vào Camera** | WebCam qua `cv2.VideoCapture(0)` | Android CameraX hardware driver (ImageFormat YUV_420_888) |
| **Từ điển 80 lớp COCO** | `TEN_VAT_THE` trong `cam_ai_core.py` | `assets/models/labels_vn.txt` (đồng bộ 100% tiếng Việt) |
| **Logic vùng an ninh (ROI)** | Tọa độ chuẩn hóa `0.0 - 1.0` (`ve_vung.py`) | Lớp phủ cảm ứng đa chạm (`GestureDetector`) chuẩn hóa `0.0 - 1.0` |
| **Cảnh báo (Alerts)** | MessageBox Windows, Chuông Beep, Telegram Bot | Android Hardware Vibration (`vibration`), Beep âm thanh ngắn |
| **Cập nhật phần mềm** | Git pull / installer PC | In-App OTA Self-Update qua Cloudflare R2 + Range 206 download |

---

## 2. QUÁ TRÌNH PHÁT TRIỂN & CÁC CỘT MỐC ĐÃ VƯỢT QUA (MILESTONES & BREAKTHROUGHS)

### Giai đoạn 1: Chuẩn bị mô hình Mobile Edge AI & Xác thực Python
1. **Chuyển đổi mô hình:** Xuất khẩu mô hình gốc `yolo11n.pt` từ `cam-ai` sang định dạng **TFLite INT8 Quantized** (`yolo11n.tflite` dung lượng siêu nhẹ ~2.9 MB, input shape `[1, 640, 640, 3]`).
2. **Xác thực trước khi nạp app:** Viết các script kiểm chứng (`scratch/scratch_test_model.py`, `scratch_test_video.py`) để đo độ chính xác trên ảnh `sample_bus.jpg` (phát hiện xe buýt 90%, người 90%) và video `video_test.mp4`.
3. **Giải mã tensor đầu ra:** Xử lý 3 tensor outputs gồm:
   - `boxes`: `[1, 8400, 4]` (tọa độ cx, cy, w, h dạng INT8)
   - `scores`: `[1, 8400]` (độ tin cậy INT8)
   - `class_indices`: `[1, 8400]` (chỉ số lớp INT8)
   Thực hiện giải lượng tử hóa (dequantization) `(val - zero_point) * scale` siêu tốc trên CPU di động.

### Giai đoạn 2: Đột phá hiệu năng — Khắc phục nghẽn từ 2 FPS lên 15–25 FPS
- **Vấn đề ban đầu:** Khi chạy camera thời gian thực, app bị nghẽn giật ở mức ~2 FPS và hình ảnh người bị kéo dài biến dạng theo chiều dọc (đổ bóng bị nhận nhầm thành `clock 91%`).
- **Nguyên nhân cốt lõi phát hiện:**
  1. Cảm biến camera Android đặt nằm ngang (Landscape), lệch 90° so với màn hình dọc điện thoại (Portrait). Nạp trực tiếp frame vào YOLO làm AI nhìn mọi vật nằm ngang, bounding box bị bóp méo.
  2. Việc dùng thư viện `image` trên Flutter để convert YUV sang RGB, sau đó resize và xoay bằng phép tính số thực (floating point) trên luồng UI tốn ~600ms/khung hình!
- **Giải pháp đột phá:** Viết giải thuật **Single-pass Direct YUV420 to RGB Tensor Converter** bằng toán tử số nguyên bit-shift (`>> 8`) kết hợp xoay 90° trực tiếp ngay khi ghi vào mảng `Uint8List` đệm sẵn `[1, 640, 640, 3]`. Không phát sinh rác bộ nhớ (Zero Allocation), đưa tốc độ camera lên **15 – 25 FPS mượt mà**.

### Giai đoạn 3: Hoàn thiện 3 chế độ sử dụng (Triple-Mode UI)
Tái cấu trúc giao diện `HomeScreen` thành 3 chế độ chuyên biệt:
1. **Camera Realtime:** Luồng quét trực tiếp từ camera sau/trước với HUD đo FPS và thời gian suy luận (ms).
2. **Đọc Ảnh tĩnh (Static Image Detection):** Chọn ảnh từ thư viện máy, nhận diện tức thì (<50ms) và vẽ bounding box sắc nét.
3. **Xem lại Video (Video Review Mode):** Phát video kèm thanh trượt Seek Bar tương tác, trích xuất khung hình native qua `MediaMetadataRetriever` trong `MainActivity.kt`.

### Giai đoạn 4: Hạ tầng phân phối & In-App Self-Update (Cloudflare Edge Stack)
Xây dựng hệ sinh thái triển khai chuẩn theo JimmyVu App Launch:
- **Cloudflare R2 Bucket:** `osiris-vision-storage` lưu trữ các bản build APK và file manifest `version.json`.
- **Cloudflare Worker:** `osiris-vision-web` phục vụ landing page tải app và API cập nhật tự động tại [https://vision.jimmyvu.me](https://vision.jimmyvu.me).
- **Kỹ thuật tải tốc độ cao:**
  - Hỗ trợ đầy đủ **HTTP Range 206 (Partial Content)** cho phép tiếp tục tải khi đứt mạng (Resume capability).
  - Bổ sung CDN Caching headers (`Cache-Control: public, max-age=86400`, `CDN-Cache-Control: public, max-age=604800`).
  - Pipeline tải APK chống nghẽn socket UI: Throttling cập nhật tiến trình (tối đa 1 lần mỗi 150ms hoặc mỗi 512KB tải thêm) giúp đường truyền đạt tốc độ tối đa của mạng.

### Giai đoạn 5: Sửa triệt để lỗi cài đặt gói Android (*"Package appears to be invalid"*)
- **Vấn đề:** Khi app tải bản cập nhật OTA về và gọi cài đặt, Android báo lỗi *"App not installed as package appears to be invalid"*.
- **Nguyên nhân & Khắc phục:**
  1. `targetSdk = 36`: SDK 36 là Android 16 Developer Preview chưa chính thức, khiến `PackageParser` trên Android 13/14/15 từ chối gói. Đã chuẩn hóa: `compileSdk = 36` (đáp ứng CameraX/TFLite) và `targetSdk = 34` (Android 14 tiêu chuẩn thương mại).
  2. Bổ sung cấu hình ký số song song `enableV1Signing = true` và `enableV2Signing = true`.
  3. Chuyển vị trí lưu file APK tải về từ `/storage/emulated/0/Download` (bị vướng Scoped Storage) sang thư mục cache an toàn của ứng dụng `getTemporaryDirectory()`.
  4. Cấp quyền đọc URI tường minh (`grantUriPermission`) qua `FileProvider` cho toàn bộ các handler của trình cài đặt hệ thống trong `MainActivity.kt`.

---

## 3. CÁC TÍNH NĂNG TƯƠNG LAI TIẾP NHẬN TỪ `cam-ai` (NEXT PHASE ROADMAP)

Dựa trên các nghiên cứu chuyên sâu ở bản `cam-ai` v2.8, các tính năng tiếp theo cần tiếp tục phát triển trên thiết bị khác:
1. **Vẽ vùng giám sát an ninh (Touch ROI):** Cho phép người dùng chạm và vẽ đa giác vùng cấm ngay trên màn hình cảm ứng điện thoại, kích hoạt rung cảnh báo (`Vibration`) khi có đối tượng bước vào.
2. **Bộ lọc nhóm vật thể (Category Filter Chips):** Thêm thanh lọc nhanh trên màn hình: `[Tất cả]`, `[Chỉ Người]`, `[Phương tiện / Xe]`, `[Đồ vật]`.
3. **Công tắc Tách ô (Tiling 2x2 with NMS):** Áp dụng bài học từ `cam-ai` v2.8 (công tắc "Nhận vật thể ở xa" chia khung thành 2x2 ô có độ phủ 35% gộp NMS) cho chế độ đọc ảnh và xem lại video để phát hiện vật thể nhỏ/ở cự ly xa.
4. **Chụp ảnh bằng chứng có khung AI (Evidence Snapshot):** Nút bấm 1 chạm chụp nhanh khung hình kèm bounding box và dấu thời gian (timestamp).

---

## 4. HƯỚNG DẪN TIẾP TỤC PHÁT TRIỂN TRÊN THIẾT BỊ KHÁC (SETUP GUIDE)

### Yêu cầu môi trường:
- **Flutter SDK:** Phiên bản 3.24.x trở lên (kênh stable).
- **Dart SDK:** 3.5.x trở lên.
- **Android SDK:** Compile SDK 36, NDK 26+, Build-tools 34.0.0+.
- **Java:** JDK 17.

### Các lệnh phát triển cơ bản:

```bash
# 1. Di chuyển vào thư mục ứng dụng di động
cd app

# 2. Cài đặt các gói phụ thuộc
flutter pub get

# 3. Kiểm tra code và cảnh báo
flutter analyze

# 4. Chạy trực tiếp trên điện thoại Android (kết nối qua USB Debugging hoặc Wifi)
flutter run

# 5. Đóng gói bản phát hành release APK
flutter build apk --release
```

*File APK hoàn thiện sẽ nằm tại: `app/build/app/outputs/flutter-apk/app-release.apk`*

### Cấu hình triển khai Web & OTA:
Thư mục `osiris-vision-web/` quản lý Cloudflare Worker. Để deploy lại trang landing page và cập nhật bản OTA:
```bash
cd osiris-vision-web

# Upload file APK mới lên Cloudflare R2
npx wrangler r2 object put "osiris-vision-storage/OsirisCameraVision-release.apk" --file="../app/build/app/outputs/flutter-apk/app-release.apk" --remote

# Upload version.json mới lên Cloudflare R2
npx wrangler r2 object put "osiris-vision-storage/version.json" --file="version.json" --remote

# Deploy lại Cloudflare Worker nếu có thay đổi giao diện web
npx wrangler deploy
```
