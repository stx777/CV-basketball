import json
import numpy as np
from scipy.signal import find_peaks

DATA_JSON_PATH = "output/ball_data.json"
BALL_DIAMETER_CM = 24.0  # Физический размер баскетбольного мяча размера 7
CONTROL_THRESHOLD_PX = 150  # Допустимое расстояние от руки до мяча для дриблинга


def calculate_metrics():
    print(f"\n--- РАСЧЕТ БАСКЕТБОЛЬНЫХ МЕТРИК ---")

    try:
        with open(DATA_JSON_PATH, "r") as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Ошибка: Файл {DATA_JSON_PATH} не найден. Сначала запустите трекер.")
        return

    fps = data["fps"]
    total_frames = data["total_frames"]

    y_array = np.array(data["y_history"], dtype=np.float64)
    x_array = np.array(data["x_history"], dtype=np.float64)
    w_array = np.array(data["w_history"], dtype=np.float64)
    shoulders_array = np.array(data["shoulders"], dtype=np.float64)
    left_wrist = data["left_wrist"]
    right_wrist = data["right_wrist"]

    # Линейная интерполяция для числовых массивов, чтобы закрыть пропуски (NaN)
    for arr in [y_array, x_array, w_array, shoulders_array]:
        nans, x = np.isnan(arr), lambda z: z.nonzero()[0]
        if np.any(nans) and not np.all(nans):
            arr[nans] = np.interp(x(nans), x(~nans), arr[~nans])

    if np.all(np.isnan(y_array)):
        print("Мяч не был обнаружен. Расчет невозможен.")
        return

    # Поиск экстремумов (отскоки об пол и мяч в верхней точке)
    bounces, _ = find_peaks(y_array, distance=10, prominence=30)
    hands, _ = find_peaks(-y_array, distance=10, prominence=30)

    real_bounces = 0
    false_bounces = 0
    shots = 0

    # Список для хранения высоты каждого отдельного удара в сантиметрах
    bounce_heights_cm = []

    # Фильтрация ударов и локальный расчет масштаба
    if len(hands) > 0:
        for bounce_idx in bounces:
            # Находим ближайший локальный минимум мяча (его верхнюю точку перед/после отскока)
            closest_hand_idx = hands[np.argmin(np.abs(hands - bounce_idx))]

            ball_x = x_array[closest_hand_idx]
            ball_y = y_array[closest_hand_idx]
            shoulder_y = shoulders_array[closest_hand_idx]

            # ФИЛЬТР 1: Бросок в кольцо
            if not np.isnan(shoulder_y) and ball_y < shoulder_y:
                shots += 1
                continue

            # ФИЛЬТР 2: Потеря мяча (Мяч далеко от обеих рук)
            lw = left_wrist[closest_hand_idx]
            rw = right_wrist[closest_hand_idx]

            dist_left = float('inf')
            dist_right = float('inf')

            if lw is not None:
                dist_left = np.hypot(ball_x - lw[0], ball_y - lw[1])
            if rw is not None:
                dist_right = np.hypot(ball_x - rw[0], ball_y - rw[1])

            # Проверяем расстояние до ближайшей руки
            if min(dist_left, dist_right) < CONTROL_THRESHOLD_PX:
                real_bounces += 1

                # --- НОВАЯ ЛОГИКА: Локальный масштаб для конкретного удара ---
                # Определяем границы текущего движения (от руки до пола)
                start_idx = min(closest_hand_idx, bounce_idx)
                end_idx = max(closest_hand_idx, bounce_idx)

                # Вырезаем кусок массива ширины мяча именно для этого удара
                local_w_array = w_array[start_idx:end_idx + 1]
                local_avg_width = np.nanmean(local_w_array)

                if local_avg_width > 0:
                    local_cm_per_px = BALL_DIAMETER_CM / local_avg_width
                    local_height_px = y_array[bounce_idx] - y_array[closest_hand_idx]
                    local_height_cm = local_height_px * local_cm_per_px
                    bounce_heights_cm.append(local_height_cm)

            else:
                false_bounces += 1

    # Итоговые расчеты
    duration_sec = total_frames / fps
    tempo = real_bounces / duration_sec if duration_sec > 0 else 0

    if len(bounce_heights_cm) > 0:
        avg_bounce_height_cm = np.mean(bounce_heights_cm)
    else:
        avg_bounce_height_cm = 0

    print(f"Продолжительность: {duration_sec:.1f} сек | Частота кадров: {int(fps)} FPS")
    print(f" - Контролируемых ударов (Дриблинг): {real_bounces}")
    print(f" - Потерь мяча (Случайные отскоки): {false_bounces}")
    print(f" - Выполненных бросков/пасов: {shots}")
    print(f" - Темп дриблинга: {tempo:.2f} ударов/сек")
    print(f" - Средняя высота отскока: {avg_bounce_height_cm:.1f} см")


if __name__ == "__main__":
    calculate_metrics()