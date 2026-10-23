from collections import deque
from pathlib import Path
import cv2
import numpy as np
import mediapipe as mp
from ultralytics import YOLO

ball_model = YOLO("yolov8s.pt")

# Класс 32 в датасете COCO — это 'sports ball' (любые мячи)
SPORTS_BALL_CLASS_ID = 32

# Хранилище последних N позиций мяча для отрисовки траектории
TRAJECTORY_LENGTH = 25
ball_track_points = deque(maxlen=TRAJECTORY_LENGTH)

# Конфигурация цветного скелета (BGR)
SKELETON_GROUPS = [
    {
        "name": "Торс",
        "color": (0, 255, 0),       # Зеленый
        "pairs": [(11, 12), (11, 23), (12, 24), (23, 24)]
    },
    {
        "name": "Левая рука",
        "color": (0, 0, 255),       # Красный
        "pairs": [(11, 13), (13, 15)]
    },
    {
        "name": "Правая рука",
        "color": (255, 0, 0),       # Синий
        "pairs": [(12, 14), (14, 16)]
    },
    {
        "name": "Левая нога",
        "color": (0, 255, 255),     # Желтый
        "pairs": [(23, 25), (25, 27)]
    },
    {
        "name": "Правая нога",
        "color": (255, 255, 0),     # Циан
        "pairs": [(24, 26), (26, 28)]
    }
]

INPUT_VIDEO_PATH = "input/test.mp4"
OUTPUT_VIDEO_PATH = "output/result.mp4"
CONFIDENCE_THRESHOLD = 0.5


def detect_ball(clean_frame):
    """
    Инференс YOLOv8s строго на ЧИСТОМ кадре с разрешением 1280.
    Возвращает: (cx, cy, radius, conf, x1, y1) или None.
    """
    results = ball_model.track(
        source=clean_frame,
        persist=True,
        classes=[SPORTS_BALL_CLASS_ID],
        conf=0.10,         # Чувствительный порог под сложные ракурсы в руках
        imgsz=640,        # Максимальная четкость мелких объектов
        tracker="bytetrack.yaml",
        verbose=False
    )

    boxes = results[0].boxes
    if len(boxes) == 0:
        return None

    # Выбираем лучший бокс по скору
    best_box = max(boxes, key=lambda b: float(b.conf[0]))
    x1, y1, x2, y2 = map(int, best_box.xyxy[0])
    conf = float(best_box.conf[0])

    w_box = x2 - x1
    h_box = y2 - y1

    # Фильтр соотношения сторон (мяч не должен быть слишком вытянутым)
    aspect_ratio = w_box / max(1, h_box)
    if not (0.45 <= aspect_ratio <= 2.2):
        return None

    cx = int((x1 + x2) / 2)
    cy = int((y1 + y2) / 2)
    radius = int(max(w_box, h_box) / 2)

    return (cx, cy, radius, conf, x1, y1)


def draw_ball_and_trajectory(frame, ball_data, width, height):
    """Отрисовывает мяч и защищенную от скачков траекторию."""
    detected_center = None

    if ball_data is not None:
        cx, cy, radius, conf, x1, y1 = ball_data
        detected_center = (cx, cy)

        # Окружность и подпись
        cv2.circle(frame, (cx, cy), radius, (255, 0, 255), 2)
        cv2.circle(frame, (cx, cy), 4, (255, 0, 255), -1)
        cv2.putText(
            frame, f"Ball {conf:.2f}", (x1, max(20, y1 - 8)),
            cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 0, 255), 2
        )

    # Интерполяция только при РЕАЛЬНОМ движении (не в самом начале)
    if detected_center is None and len(ball_track_points) >= 2:
        p1 = ball_track_points[0]
        p2 = ball_track_points[1]
        if p1 is not None and p2 is not None:
            vx = p1[0] - p2[0]
            vy = p1[1] - p2[1]
            # Если скачок скорости адекватный (не телепортация через пол-экрана)
            speed = np.hypot(vx, vy)
            if speed < 120:
                pred_x = int(p1[0] + vx)
                pred_y = int(p1[1] + vy)
                # Проверяем, что точка внутри кадра
                if 0 <= pred_x < width and 0 <= pred_y < height:
                    detected_center = (pred_x, pred_y)

    ball_track_points.appendleft(detected_center)

    # Отрисовка траектории с защитой от резких скачков
    for i in range(1, len(ball_track_points)):
        pt_curr = ball_track_points[i - 1]
        pt_prev = ball_track_points[i]

        if pt_curr is None or pt_prev is None:
            continue

        # Фильтр артефактов: если расстояние между точками > 150 px, отрезок не рисуем
        dist = np.hypot(pt_curr[0] - pt_prev[0], pt_curr[1] - pt_prev[1])
        if dist > 150:
            continue

        thickness = int(np.sqrt(TRAJECTORY_LENGTH / float(i + 1)) * 2.2)
        cv2.line(frame, pt_curr, pt_prev, (0, 140, 255), thickness)


def draw_skeleton(frame, landmarks, width, height):

    for group in SKELETON_GROUPS:
        color = group["color"]
        for idx_start, idx_end in group["pairs"]:
            pt_start = landmarks[idx_start]
            pt_end = landmarks[idx_end]

            if pt_start.visibility > CONFIDENCE_THRESHOLD and pt_end.visibility > CONFIDENCE_THRESHOLD:
                x1, y1 = int(pt_start.x * width), int(pt_start.y * height)
                x2, y2 = int(pt_end.x * width), int(pt_end.y * height)
                cv2.line(frame, (x1, y1), (x2, y2), color, thickness=3)

    for lm in landmarks:
        if lm.visibility > CONFIDENCE_THRESHOLD:
            cx, cy = int(lm.x * width), int(lm.y * height)
            cv2.circle(frame, (cx, cy), radius=4,
                       color=(255, 255, 255), thickness=-1)


def main():
    input_file = Path(INPUT_VIDEO_PATH)
    if not input_file.exists():
        print(f"Ошибка: положите входное видео в '{INPUT_VIDEO_PATH}'")
        return

    cap = cv2.VideoCapture(str(input_file))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(OUTPUT_VIDEO_PATH, fourcc, fps, (width, height))

    mp_pose = mp.solutions.pose
    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=2,
        smooth_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5
    ) as pose:

        frame_idx = 0
        print(f"Обработка видео (скелет + мяч): {total_frames} кадров...")

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            clean_frame = frame.copy()

            rgb_frame = cv2.cvtColor(clean_frame, cv2.COLOR_BGR2RGB)
            pose_results = pose.process(rgb_frame)

            ball_data = detect_ball(clean_frame)

            if pose_results.pose_landmarks:
                draw_skeleton(
                    frame, pose_results.pose_landmarks.landmark, width, height)

            draw_ball_and_trajectory(frame, ball_data, width, height)

            out.write(frame)
            frame_idx += 1

            if frame_idx % 30 == 0 or frame_idx == total_frames:
                print(f"Обработано {frame_idx}/{total_frames} кадров...")

    cap.release()
    out.release()
    print(f"\nГотово! Видео сохранено в: '{OUTPUT_VIDEO_PATH}'")


if __name__ == "__main__":
    main()
