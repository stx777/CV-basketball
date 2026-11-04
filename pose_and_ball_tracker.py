import gc
import json
from collections import deque
from pathlib import Path
import cv2
import numpy as np
import mediapipe as mp
from ultralytics import YOLO

ball_model = YOLO("basketball_best.pt")


# Хранилище последних N позиций мяча для отрисовки траектории
TRAJECTORY_LENGTH = 7
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

INPUT_VIDEO_PATH = "input/test8.mp4"
OUTPUT_VIDEO_PATH = "output/result26.mp4"
DATA_JSON_PATH = "output/ball_data.json"
CONFIDENCE_THRESHOLD = 0.5


def detect_ball(clean_frame):
    """Чистый инференс YOLO без вмешательства ByteTrack."""
    results = ball_model.predict(
        source=clean_frame,
        classes=[0],       # только мяч
        conf=0.15,         # чувствительный порог для смазанного мяча
        imgsz=640,
        verbose=False,
        stream=True        # возвращает генератор
    )

    # Извлекаем результат из генератора через цикл
    for r in results:
        boxes = r.boxes
        if len(boxes) == 0:
            return None

        # Берем лучший бокс по уверенности
        best_box = max(boxes, key=lambda b: float(b.conf[0]))
        conf = float(best_box.conf[0])

        x1, y1, x2, y2 = map(int, best_box.xyxy[0])
        cx = int((x1 + x2) / 2)
        cy = int((y1 + y2) / 2)

        return (cx, cy, conf, x1, y1, x2, y2)

    return None


def draw_ball_and_trajectory(frame, ball_data, width, height):
    """Аккуратный исчезающий хвост кометы без паутины."""
    if ball_data is not None:
        cx, cy, conf, x1, y1, x2, y2 = ball_data

        # 1. Рисуем синий квадрат и скор
        cv2.rectangle(frame, (x1, y1), (x2, y2), (255, 0, 0), thickness=3)
        cv2.putText(
            frame, f"Ball {conf:.2f}", (x1, max(20, y1 - 10)),
            cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 0, 0), 2
        )

        # 2. ВОТ ЭТА СТРОЧКА: добавляем точку в историю траектории
        ball_track_points.appendleft((cx, cy))

    else:
        # Если мяч временно пропал — плавно укорачиваем хвост
        if len(ball_track_points) > 0:
            ball_track_points.pop()

    # 3. Отрисовка траектории
    for i in range(1, len(ball_track_points)):
        pt_curr = ball_track_points[i - 1]
        pt_prev = ball_track_points[i]

        # Защита от резких скачков (если мяч телепортировался > 100px)
        if np.hypot(pt_curr[0] - pt_prev[0], pt_curr[1] - pt_prev[1]) > 100:
            break

        thickness = max(1, int((TRAJECTORY_LENGTH - i) * 0.8))
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

    # Создаем папку output, если ее нет
    Path(OUTPUT_VIDEO_PATH).parent.mkdir(parents=True, exist_ok=True)

    cap = cv2.VideoCapture(str(input_file))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(OUTPUT_VIDEO_PATH, fourcc, fps, (width, height))

    y_history = []
    mp_pose = mp.solutions.pose

    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
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

            if ball_data is not None:
                y_history.append(ball_data[1])
            else:
                y_history.append(None)  # None легально конвертируется в JSON (станет null)

            out.write(frame)
            frame_idx += 1

            if frame_idx % 30 == 0 or frame_idx == total_frames:
                print(f"Обработано {frame_idx}/{total_frames} кадров...")

            del clean_frame
            del rgb_frame
            del pose_results
            del ball_data
            gc.collect()

    cap.release()
    out.release()
    print(f"Видео сохранено в: '{OUTPUT_VIDEO_PATH}'")

    # Экспорт данных в JSON-отчет
    report = {
        "fps": fps,
        "total_frames": total_frames,
        "y_history": y_history
    }
    with open(DATA_JSON_PATH, "w") as f:
        json.dump(report, f)
    print(f"Данные для метрик сохранены в: '{DATA_JSON_PATH}'")


if __name__ == "__main__":
    main()
