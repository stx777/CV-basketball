from ultralytics import YOLO

if __name__ == '__main__':
    model = YOLO('yolov8n.pt')

    results = model.train(
        data='dataset/data.yaml',
        epochs=50,
        imgsz=640,
        batch=16,
        device=0,
        workers=4,
        name='basketball_yolo8n'
    )
