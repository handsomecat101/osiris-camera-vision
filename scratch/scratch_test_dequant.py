import ai_edge_litert.interpreter as litert
import numpy as np
import cv2

model_path = r'h:\AI Project\osiris camera vision\app\assets\models\yolo11n.tflite'
interpreter = litert.Interpreter(model_path=model_path)
interpreter.allocate_tensors()

inp_details = interpreter.get_input_details()
out_details = interpreter.get_output_details()

img = cv2.imread(r'h:\AI Project\cam-ai\sample_bus.jpg')
h_orig, w_orig = img.shape[:2]
img_resized = cv2.resize(img, (640, 640))
img_rgb = cv2.cvtColor(img_resized, cv2.COLOR_BGR2RGB)
input_data = np.expand_dims(img_rgb, axis=0)

interpreter.set_tensor(inp_details[0]['index'], input_data)
interpreter.invoke()

# Map outputs by name or order
out_map = {out['name']: interpreter.get_tensor(out['index']) for out in out_details}
print('Output keys:', list(out_map.keys()))

boxes_q = out_map['boxes'][0] # shape (8400, 4)
scores_q = out_map['scores'][0] # shape (8400,)
classes = out_map['class_idx'][0] # shape (8400,)

# Dequantization parameters
# boxes: scale = 3.2448902130126953, zp = 29
# scores: scale = 0.00390625, zp = 0
b_scale = 3.2448902130126953
b_zp = 29
s_scale = 0.00390625

boxes = (boxes_q.astype(np.float32) - b_zp) * b_scale # coordinates in 640x640 space
scores = scores_q.astype(np.float32) * s_scale

print('Max score:', scores.max())
conf_threshold = 0.3

detections = []
for i in range(8400):
    if scores[i] >= conf_threshold:
        cx, cy, w, h = boxes[i]
        cls_id = int(classes[i])
        score = float(scores[i])
        left = cx - w / 2
        top = cy - h / 2
        right = cx + w / 2
        bottom = cy + h / 2
        detections.append((cls_id, score, left, top, right, bottom))

print(f'Found {len(detections)} raw detections >= {conf_threshold}:')
for d in detections[:15]:
    print(f' - Class {d[0]}: score={d[1]:.2f}, box=({d[2]:.1f}, {d[3]:.1f}, {d[4]:.1f}, {d[5]:.1f})')
