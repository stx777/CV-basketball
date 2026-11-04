import json
import numpy as np
from scipy.signal import find_peaks

DATA_JSON_PATH = "output/ball_data.json"


def calculate_metrics():
    print(f"\nРАСЧЕТ БАСКЕТБОЛЬНЫХ МЕТРИК")

    try:
        with open(DATA_JSON_PATH, "r") as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Ошибка: Файл {DATA_JSON_PATH} не найден. Сначала запустите трекер.")
        return

    fps = data["fps"]
    total_frames = data["total_frames"]

    # Конвертируем список в массив numpy (значения null автоматически станут np.nan)
    y_array = np.array(data["y_history"], dtype=np.float64)

    # 1. Восстановление пропусков (линейная интерполяция)
    nans, x = np.isnan(y_array), lambda z: z.nonzero()[0]
    if np.any(nans) and not np.all(nans):
        y_array[nans] = np.interp(x(nans), x(~nans), y_array[~nans])

    if not np.all(nans):
        # 2. Поиск отскоков об пол (локальные максимумы по оси Y)
        bounces, _ = find_peaks(y_array, distance=10, prominence=30)

        # 3. Поиск мяча в руке (локальные минимумы)
        hands, _ = find_peaks(-y_array, distance=10, prominence=30)

        # 4. Вычисление темпа (ударов в секунду)
        duration_sec = total_frames / fps
        tempo = len(bounces) / duration_sec if duration_sec > 0 else 0

        # 5. Вычисление высоты отскока
        if len(bounces) > 0 and len(hands) > 0:
            avg_floor_y = np.mean(y_array[bounces])
            avg_hand_y = np.mean(y_array[hands])
            avg_bounce_height = avg_floor_y - avg_hand_y
        else:
            avg_bounce_height = 0

        print(f"Анализ видео ({duration_sec:.1f} сек при {fps} FPS):")
        print(f" - Всего ударов об пол: {len(bounces)}")
        print(f" - Темп дриблинга: {tempo:.2f} ударов/сек")
        print(f" - Средняя амплитуда отскока: {avg_bounce_height:.1f} пикселей")
    else:
        print("Мяч не был обнаружен ни на одном кадре. Расчет метрик невозможен.")


if __name__ == "__main__":
    calculate_metrics()