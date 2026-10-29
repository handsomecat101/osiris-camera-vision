import os
import cv2
import numpy as np

model_path = r'h:\AI Project\osiris camera vision\app\assets\models\yolo11n.tflite'
print('Model path:', model_path)
print('File size:', os.path.getsize(model_path))

try:
    # Check if tflite runtime or onnxruntime is available
    import tflite_runtime.interpreter as tflite
    interpreter = tflite.Interpreter(model_path=model_path)
    interpreter.allocate_tensors()
    print('TFLite runtime allocated tensors successfully!')
    print('Inputs:', interpreter.get_input_details())
    print('Outputs:', interpreter.get_output_details())
except Exception as e:
    print('tflite_runtime error:', e)

try:
    from ultralytics import YOLO
    model = YOLO(model_path)
    print('Ultralytics loaded model successfully!')
    # Test inference on sample_bus.jpg
    res = model.predict(r'h:\AI Project\cam-ai\sample_bus.jpg')
    print('Inference result boxes:', len(res[0].boxes))
    for b in res[0].boxes:
        print(' - cls:', int(b.cls[0]), 'conf:', float(b.conf[0]))
except Exception as e:
    print('YOLO predict error:', e)
