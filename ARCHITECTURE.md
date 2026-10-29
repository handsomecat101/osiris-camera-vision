# KIẾN TRÚC KỸ THUẬT — Osiris Camera Vision

> Tài liệu này mô tả chi tiết kiến trúc tầng, luồng xử lý dữ liệu từ camera đến kết quả suy luận AI trên thiết bị di động Android.

---

## 1. Sơ Đồ Kiến Trúc Hệ Thống (System Architecture)

```
[ Camera Sensor / File Video ]
              │
              ▼
    [ CameraX / VideoPlayer ] ──> Raw Image Stream (YUV420 / RGBA)
              │
              ▼
   [ Image Preprocessing ] ─────> Resize (640x640), Normalize (0.0 - 1.0)
              │
              ▼
 [ TFLite Engine (NNAPI/GPU) ] ──> Run YOLO11n.tflite
              │
              ▼
 [ Postprocessing & NMS ] ─────> Bounding Boxes, Class IDs, Scores
              │
              ▼
 [ Spatial & Business Logic ] ──> Check ROI (vùng vẽ tay), Loitering (đứng lâu)
              │
      ┌───────┴────────────────────────┐
      ▼                                ▼
[ Flutter Canvas Overlay ]    [ Alert Dispatcher ]
(Vẽ khung, nhãn tiếng Việt)    (Rung máy, chuông, snapshot)
```

---

## 2. Các Tầng Chức Năng (Layered Architecture)

### 2.1 Tầng Presentation (Giao Diện & Tương Tác)
- **Camera Preview Screen:** Khung hiển thị luồng hình ảnh toàn màn hình với tỉ lệ 16:9 hoặc 4:3.
- **Custom Painter Overlay:** Một lớp `Canvas` vẽ đè lên trên luồng video:
  - Khung bao (Bounding box) với màu sắc đặc trưng theo từng nhóm vật thể.
  - Nhãn tiếng Việt kèm tỷ lệ phần trăm độ tin cậy.
  - Vùng cảnh báo (ROI Polygon) vẽ bằng cảm ứng đa điểm.
- **Control Bar & Bottom Sheet:**
  - Nút chuyển đổi nguồn (Live Camera / File Video).
  - Thanh chọn nhanh nhóm vật thể (Người / Xe cộ / Đồ dùng / Động vật).
  - Nút chụp ảnh nhanh (Snapshot) và bật/tắt cảnh báo âm thanh.

### 2.2 Tầng Core AI & Inference (Mobile Edge AI)
- **TensorFlow Lite Engine:** Nạp mô hình `yolo11n.tflite` vào bộ nhớ và gán bộ tăng tốc:
  - *Android NNAPI:* Tận dụng bộ vi xử lý thần kinh (NPU) trên các dòng chip Snapdragon, MediaTek Dimensity, Google Tensor.
  - *GPU Delegate:* Phương án dự phòng kích hoạt OpenCL/OpenGL GPU nếu thiết bị không có NPU chuyên biệt.
- **Image Conversion (C++ / FFI hoặc Isolates):**
  - Chuyển đổi định dạng ảnh đầu vào từ `YUV420_888` (chuẩn Android Camera) sang mảng `Float32List` 3 kênh RGB chuẩn hóa `[1, 640, 640, 3]`.

### 2.3 Tầng Nghiệp Vụ Không Gian (Spatial Logic)
*Kế thừa từ giải thuật của [`cam-ai/cam_ai_core.py`](file:///h:/AI%20Project/cam-ai/cam_ai_core.py):*
- **Point-in-Polygon (Ray casting):** Xác định tâm của hộp vật thể `(cx, cy)` có nằm trong đa giác cảnh báo do người dùng vẽ tay trên màn hình hay không.
- **Loitering Tracker:** Tính toán khoảng thời gian một vật thể duy trì vị trí bên trong khu vực ROI. Khi vượt ngưỡng cài đặt (ví dụ: > 5 giây), kích hoạt sự kiện cảnh báo.

---

## 3. Quản Lý Tài Nguyên & Hiệu Năng Trên Di Động
- **Cơ chế Isolate (Background Worker):** Toàn bộ việc tiền xử lý ảnh và chạy suy luận AI được đưa vào một luồng riêng (`Flutter Isolate`), đảm bảo giao diện 60 FPS không bao giờ bị đơ hay giật khung hình.
- **Drop-frame Thích Ứng:** Nếu một khung hình mất 25ms để xử lý, các khung hình camera trung gian sẽ được bỏ qua an toàn, giúp máy mát và tiết kiệm pin tối đa.
