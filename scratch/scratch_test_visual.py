import ai_edge_litert.interpreter as litert
import numpy as np
import cv2

model_path = r'h:\AI Project\osiris camera vision\app\assets\models\yolo11n.tflite'
interpreter = litert.Interpreter(model_path=model_path)
interpreter.allocate_tensors()

img = cv2.imread(r'h:\AI Project\cam-ai\sample_bus.jpg')
h_orig, w_orig = img.shape[:2]
img_resized = cv2.resize(img, (640, 640))
img_rgb = cv2.cvtColor(img_resized, cv2.COLOR_BGR2RGB)
input_data = np.expand_dims(img_rgb, axis=0)

interpreter.set_tensor(0, input_data)
interpreter.invoke()

out_map = {out['name']: interpreter.get_tensor(out['index']) for out in interpreter.get_output_details()}
boxes_q = out_map['boxes'][0]
scores_q = out_map['scores'][0]
classes = out_map['class_idx'][0]

b_scale = 3.2448902130126953
b_zp = 29
s_scale = 0.00390625

boxes = (boxes_q.astype(np.float32) - b_zp) * b_scale
scores = scores_q.astype(np.float32) * s_scale

# Filter with conf >= 0.35 and NMS
cand_boxes = []
cand_scores = []
cand_classes = []

for i in range(8400):
    if scores[i] >= 0.35:
        cand_boxes.append(boxes[i])
        cand_scores.append(scores[i])
        cand_classes.append(int(classes[i]))

cand_boxes = np.array(cand_boxes)
cand_scores = np.array(cand_scores)
cand_classes = np.array(cand_classes)

# NMS with cv2.dnn.NMSBoxes
# boxes for NMSBoxes: [x, y, w, h]
nms_boxes = []
for b in cand_boxes:
    x1, y1, x2, y2 = b
    nms_boxes.append([int(x1), int(y1), int(x2 - x1), int(y2 - y1)])

indices = cv2.dnn.NMSBoxes(nms_boxes, cand_scores.tolist(), 0.35, 0.45)
print('Detections after NMS:', len(indices))

output_img = img_resized.copy()
for idx in indices:
    i = int(idx)
    x1, y1, x2, y2 = cand_boxes[i]
    cls_id = cand_classes[i]
    score = cand_scores[i]
    print(f'Detected: class {cls_id}, score {score:.2f}, box: [{x1:.1f}, {y1:.1f}, {x2:.1f}, {y2:.1f}]')
    cv2.rectangle(output_img, (int(x1), int(y1)), (int(x2), int(y2)), (0, 255, 0), 2)
    cv2.putText(output_img, f'Cls {cls_id}: {score:.2f}', (int(x1), int(y1) - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)

cv2.imwrite(r'h:\AI Project\osiris camera vision\test_result_bus.jpg', output_img)
print('Saved result to test_result_bus.jpg successfully!')
