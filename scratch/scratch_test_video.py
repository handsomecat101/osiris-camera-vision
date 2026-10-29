import ai_edge_litert.interpreter as litert
import numpy as np
import cv2

model_path = r'h:\AI Project\osiris camera vision\app\assets\models\yolo11n.tflite'
interpreter = litert.Interpreter(model_path=model_path)
interpreter.allocate_tensors()

video_path = r'h:\AI Project\cam-ai\video_test.mp4'
cap = cv2.VideoCapture(video_path)

b_scale = 3.2448902130126953
b_zp = 29
s_scale = 0.00390625

frame_idx = 0
total_detected_frames = 0
total_objects = 0

print(f'Starting test on video: {video_path}')
while cap.isOpened() and frame_idx < 100:
    ret, frame = cap.read()
    if not ret:
        break
    
    frame_idx += 1
    # Test every 5th frame
    if frame_idx % 5 != 0:
        continue
    
    img_resized = cv2.resize(frame, (640, 640))
    img_rgb = cv2.cvtColor(img_resized, cv2.COLOR_BGR2RGB)
    input_data = np.expand_dims(img_rgb, axis=0)

    interpreter.set_tensor(0, input_data)
    interpreter.invoke()

    out_map = {out['name']: interpreter.get_tensor(out['index']) for out in interpreter.get_output_details()}
    boxes_q = out_map['boxes'][0]
    scores_q = out_map['scores'][0]
    classes = out_map['class_idx'][0]

    boxes = (boxes_q.astype(np.float32) - b_zp) * b_scale
    scores = scores_q.astype(np.float32) * s_scale

    cand_boxes = []
    cand_scores = []
    cand_classes = []

    for i in range(8400):
        if scores[i] >= 0.35:
            cand_boxes.append(boxes[i])
            cand_scores.append(scores[i])
            cand_classes.append(int(classes[i]))

    if cand_boxes:
        nms_boxes = [[int(b[0]), int(b[1]), int(b[2]-b[0]), int(b[3]-b[1])] for b in cand_boxes]
        indices = cv2.dnn.NMSBoxes(nms_boxes, cand_scores, 0.35, 0.45)
        count = len(indices)
        if count > 0:
            total_detected_frames += 1
            total_objects += count
            labels = [f"Class {cand_classes[int(i)]} ({cand_scores[int(i)]:.2f})" for i in indices]
            print(f"Frame {frame_idx}: Detected {count} objects: {', '.join(labels[:4])}")

cap.release()
print(f'Done testing 100 frames! Detected objects in {total_detected_frames} sampled frames, total {total_objects} objects.')
