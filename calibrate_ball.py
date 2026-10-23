import cv2
import numpy as np

VIDEO_PATH = "input/test.mp4"

def nothing(x):
    pass

cv2.namedWindow("Ball HSV Tuner")
cv2.resizeWindow("Ball HSV Tuner", 640, 320)

# Стартовые значения под яркий волейбольный желтый
cv2.createTrackbar("H_min", "Ball HSV Tuner", 20, 179, nothing)
cv2.createTrackbar("H_max", "Ball HSV Tuner", 40, 179, nothing)
cv2.createTrackbar("S_min", "Ball HSV Tuner", 100, 255, nothing)
cv2.createTrackbar("S_max", "Ball HSV Tuner", 255, 255, nothing)
cv2.createTrackbar("V_min", "Ball HSV Tuner", 100, 255, nothing)
cv2.createTrackbar("V_max", "Ball HSV Tuner", 255, 255, nothing)

cap = cv2.VideoCapture(VIDEO_PATH)

while True:
    ret, frame = cap.read()
    if not ret:
        cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
        continue

    small_frame = cv2.resize(frame, (960, 540))
    hsv = cv2.cvtColor(small_frame, cv2.COLOR_BGR2HSV)

    h_min = cv2.getTrackbarPos("H_min", "Ball HSV Tuner")
    h_max = cv2.getTrackbarPos("H_max", "Ball HSV Tuner")
    s_min = cv2.getTrackbarPos("S_min", "Ball HSV Tuner")
    s_max = cv2.getTrackbarPos("S_max", "Ball HSV Tuner")
    v_min = cv2.getTrackbarPos("V_min", "Ball HSV Tuner")
    v_max = cv2.getTrackbarPos("V_max", "Ball HSV Tuner")

    lower = np.array([h_min, s_min, v_min])
    upper = np.array([h_max, s_max, v_max])

    mask = cv2.inRange(hsv, lower, upper)
    mask = cv2.erode(mask, None, iterations=2)
    mask = cv2.dilate(mask, None, iterations=2)

    result_preview = cv2.bitwise_and(small_frame, small_frame, mask=mask)

    cv2.imshow("Mask (White = Ball)", mask)
    cv2.imshow("Result Preview", result_preview)

    if cv2.waitKey(16) & 0xFF == 27:
        print(f"Подобранные границы:")
        print(f"BALL_LOWER_HSV = np.array([{h_min}, {s_min}, {v_min}])")
        print(f"BALL_UPPER_HSV = np.array([{h_max}, {s_max}, {v_max}])")
        break

cap.release()
cv2.destroyAllWindows()