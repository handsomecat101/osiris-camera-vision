import ai_edge_litert.interpreter as litert
import numpy as np
import cv2

model_path = r'h:\AI Project\osiris camera vision\app\assets\models\yolo11n.tflite'
interpreter = litert.Interpreter(model_path=model_path)
interpreter.allocate_tensors()

print('=== INPUT DETAILS ===')
for inp in interpreter.get_input_details():
    print(inp)

print('=== OUTPUT DETAILS ===')
for out in interpreter.get_output_details():
    print(out)

# Now test inference with UINT8 on sample_bus.jpg!
img = cv2.imread(r'h:\AI Project\cam-ai\sample_bus.jpg')
img_resized = cv2.resize(img, (640, 640))
img_rgb = cv2.cvtColor(img_resized, cv2.COLOR_BGR2RGB)
input_data = np.expand_dims(img_rgb, axis=0) # shape (1, 640, 640, 3), dtype uint8
print('Input data shape:', input_data.shape, 'dtype:', input_data.dtype)

interpreter.set_tensor(interpreter.get_input_details()[0]['index'], input_data)
interpreter.invoke()

out_tensor = interpreter.get_tensor(interpreter.get_output_details()[0]['index'])
print('Output data shape:', out_tensor.shape, 'dtype:', out_tensor.dtype, 'min:', out_tensor.min(), 'max:', out_tensor.max())
