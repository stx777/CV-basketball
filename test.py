import cv2
import time
from ultralytics import YOLO

model = YOLO('runs/detect/basketball_yolo8n-2/weights/best.pt')

input_video_path = 'input/test2.mp4'
cap = cv2.VideoCapture(input_video_path)

fps = int(cap.get(cv2.CAP_PROP_FPS))
width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

output_video_path = 'output/result16.mp4'
fourcc = cv2.VideoWriter_fourcc(*'mp4v')
out = cv2.VideoWriter(output_video_path, fourcc, fps, (width, height))
start_time = time.perf_counter()
print("Обработка видео запущена...")

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break

    results = model.predict(frame, classes=[0], conf=0.4, verbose=False)

    annotated_frame = results[0].plot()

    out.write(annotated_frame)
end_time = time.perf_counter()
time_of_work = end_time - start_time
cap.release()
out.release()
print(
    f"Готово! Видео сохранено в: {output_video_path}, видео обработано за {time_of_work:.4f} секунд")
