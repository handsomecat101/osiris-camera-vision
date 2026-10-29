import ai_edge_litert.interpreter as litert
import numpy as np
import cv2

model_path = r'h:\AI Project\osiris camera vision\app\assets\models\yolo11n.tflite'
interpreter = litert.Interpreter(model_path=model_path)
interpreter.allocate_tensors()

img = cv2.imread(r'h:\AI Project\cam-ai\sample_bus.jpg')
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

# Find the highest scoring bus detection (class 5)
bus_indices = [i for i in range(8400) if classes[i] == 5 and scores[i] > 0.7]
print('Found bus indices:', bus_indices)
for idx in bus_indices[:5]:
    raw = boxes_q[idx]
    deq = boxes[idx]
    print(f'Idx {idx}: score={scores[idx]:.3f}, raw={raw}, deq={deq}')
