import cv2
import numpy as np
from ultralytics import YOLO

model = YOLO("basketball_best.pt")

# Инициализируем фильтр Кальмана для физики мяча (координаты X, Y и скорости Vx, Vy)
kalman = cv2.KalmanFilter(4, 2)
kalman.measurementMatrix = np.array([[1, 0, 0, 0],
                                     [0, 1, 0, 0]], np.float32)
kalman.transitionMatrix = np.array([[1, 0, 1, 0],
                                    [0, 1, 0, 1],
                                    [0, 0, 1, 0],
                                    [0, 0, 0, 1]], np.float32)
kalman.processNoiseCov = np.eye(4, dtype=np.float32) * 0.03

cap = cv2.VideoCapture("input/test9.mp4")
width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
fps = cap.get(cv2.CAP_PROP_FPS) or 30.0

out = cv2.VideoWriter("output/kalman_result.mp4",
                      cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))

frames_without_ball = 0
last_radius = 25

print("Запуск умного трекинга с предсказанием физики...")

while cap.isOpened():
    ret, frame = cap.read()
    if not ret:
        break

    # 1. Шаг предсказания Кальмана (где мяч ДОЛЖЕН быть по законам физики)
    prediction = kalman.predict()
    pred_x, pred_y = int(prediction[0][0]), int(prediction[1][0])

    # 2. Чистый predict БЕЗ ByteTrack (чтобы трекер не выкидывал далекие боксы)
    results = model.predict(
        frame, classes=[0], conf=0.15, imgsz=640, verbose=False)
    boxes = results[0].boxes

    detected = False
    if len(boxes) > 0:
        # Берем самый уверенный бокс
        best_box = max(boxes, key=lambda b: float(b.conf[0]))
        x1, y1, x2, y2 = map(int, best_box.xyxy[0])
        cx = int((x1 + x2) / 2)
        cy = int((y1 + y2) / 2)
        last_radius = int(max(x2 - x1, y2 - y1) / 2)

        # Передаем реальную детекцию в Кальман для коррекции
        measurement = np.array([[np.float32(cx)], [np.float32(cy)]])
        kalman.correct(measurement)

        # Рисуем детекцию (СИНИЙ квадрат)
        cv2.rectangle(frame, (x1, y1), (x2, y2), (255, 0, 0), 3)
        cv2.putText(frame, f"YOLO {float(best_box.conf[0]):.2f}", (x1, max(20, y1 - 10)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 0, 0), 2)
        detected = True
        frames_without_ball = 0
    else:
        frames_without_ball += 1

    # 3. ЕСЛИ НЕЙРОСЕТЬ ПРОПУСТИЛА КАДР (смазывание в воздухе)
    # Если мяч пропал не больше чем на 4 кадра подряд — рисуем предсказание физики!
    if not detected and frames_without_ball <= 4:
        x1_pred = pred_x - last_radius
        y1_pred = pred_y - last_radius
        x2_pred = pred_x + last_radius
        y2_pred = pred_y + last_radius

        # Рисуем предсказанный физикой квадрат (ЗЕЛЕНЫЙ — чтобы ты видел работу физики)
        cv2.rectangle(frame, (x1_pred, y1_pred),
                      (x2_pred, y2_pred), (0, 255, 0), 2)
        cv2.putText(frame, "Physics (Kalman)", (x1_pred, max(20, y1_pred - 10)),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)

    out.write(frame)

cap.release()
out.release()
print("Готово! Результат в: output/kalman_result.mp4")
