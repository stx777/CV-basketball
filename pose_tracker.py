from pathlib import Path
import cv2
import mediapipe as mp

SKELETON_GROUPS = [
    {
        "name": "Торс",
        "color": (0, 255, 0),       # Зеленый
        "pairs": [
            (11, 12),  # Плечи
            (11, 23),  # Левое плечо -> Левое бедро
            (12, 24),  # Правое плечо -> Правое бедро
            (23, 24),  # Бедра
        ]
    },
    {
        "name": "Левая рука",
        "color": (0, 0, 255),       # Красный
        "pairs": [
            (11, 13),  # Левое плечо -> Левый локоть
            (13, 15),  # Левый локоть -> Левое запястье
        ]
    },
    {
        "name": "Правая рука",
        "color": (255, 0, 0),       # Синий
        "pairs": [
            (12, 14),  # Правое плечо -> Правый локоть
            (14, 16),  # Правый локоть -> Правое запястье
        ]
    },
    {
        "name": "Левая нога",
        "color": (0, 255, 255),     # Желтый
        "pairs": [
            (23, 25),  # Левое бедро -> Левое колено
            (25, 27),  # Левое колено -> Левая лодыжка
        ]
    },
    {
        "name": "Правая нога",
        "color": (255, 255, 0),     # Бирюзовый
        "pairs": [
            (24, 26),  # Правое бедро -> Правое колено
            (26, 28),  # Правое колено -> Правая лодыжка
        ]
    }
]

INPUT_VIDEO_PATH = "input/test.mp4"
OUTPUT_VIDEO_PATH = "output/result.mp4"
CONFIDENCE_THRESHOLD = 0.5  # Порог отсечения шумных/невидимых точек


def draw_skeleton(frame, landmarks, width, height):
    """Отрисовывает разноцветные кости и суставы поверх кадра."""
    # 1. Цветные отрезки
    for group in SKELETON_GROUPS:
        color = group["color"]
        for idx_start, idx_end in group["pairs"]:
            pt_start = landmarks[idx_start]
            pt_end = landmarks[idx_end]

            if pt_start.visibility > CONFIDENCE_THRESHOLD and pt_end.visibility > CONFIDENCE_THRESHOLD:
                x1, y1 = int(pt_start.x * width), int(pt_start.y * height)
                x2, y2 = int(pt_end.x * width), int(pt_end.y * height)
                cv2.line(frame, (x1, y1), (x2, y2), color, thickness=3)

    # 2. Суставы (белые кружки)
    for lm in landmarks:
        if lm.visibility > CONFIDENCE_THRESHOLD:
            cx, cy = int(lm.x * width), int(lm.y * height)
            cv2.circle(frame, (cx, cy), radius=4, color=(255, 255, 255), thickness=-1)


def main():
    input_file = Path(INPUT_VIDEO_PATH)
    if not input_file.exists():
        print(f"Ошибка: положите тестовое видео в папку '{INPUT_VIDEO_PATH}'")
        return

    cap = cv2.VideoCapture(str(input_file))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fps = cap.get(cv2.CAP_PROP_FPS) or 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))

    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    out = cv2.VideoWriter(OUTPUT_VIDEO_PATH, fourcc, fps, (width, height))

    mp_pose = mp.solutions.pose
    
    # model_complexity=1 — золотая середина по скорости/точности BlazePose
    # static_image_mode=False включает внутренний трекер между кадрами (без него FPS падает в разы)
    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        smooth_landmarks=True,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5
    ) as pose:

        frame_idx = 0
        print(f"Старт обработки: {total_frames} кадров, исходный FPS: {fps:.1f}")

        while cap.isOpened():
            ret, frame = cap.read()
            if not ret:
                break

            # BGR -> RGB для MediaPipe
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            results = pose.process(rgb_frame)

            if results.pose_landmarks:
                draw_skeleton(frame, results.pose_landmarks.landmark, width, height)

            out.write(frame)
            frame_idx += 1

            if frame_idx % 30 == 0 or frame_idx == total_frames:
                print(f"Обработано {frame_idx}/{total_frames} кадров...")

    cap.release()
    out.release()
    print(f"\nГотово! Результат сохранен в: '{OUTPUT_VIDEO_PATH}'")


if __name__ == "__main__":
    main()