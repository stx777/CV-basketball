from ultralytics import YOLO
model = YOLO('basketball_best.pt')
model.export(
    format='coreml',
    half=True,    # FP16: ускоряет работу на Apple Neural Engine в 2 раза
    # Вшивает пост-обработку прямо в модель (на телефоне не придется писать сложный код фильтрации рамок)
    nms=True,
    imgsz=640
)
print("\nУспешно! Модель для iPhone готова.")
