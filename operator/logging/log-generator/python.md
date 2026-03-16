## Generate JSON formatted logs of multi-line messages

### Build python-app image
```bash
cat > Dockerfile << EOF
FROM docker.io/library/python:3.9-slim
WORKDIR /app
COPY app.py /app
CMD ["python", "/app/app.py"]
EOF

cat > app.py << EOF
import logging
import json
import time
from datetime import datetime

class StructuredMessage(object):
    def __init__(self, message, **kwargs):
        self.message = message
        self.kwargs = kwargs

    def to_json(self):
        return json.dumps({
            'message': self.message,
            'timestamp': datetime.now().isoformat(),
            'log_level': 'INFO',
            'user_id': '12345',
            **self.kwargs
        })

def setup_logging():
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)

def log_structured_message(message, **kwargs):
    logging.info(StructuredMessage(message, **kwargs).to_json())

setup_logging()

while True:
    log_structured_message("This is a structured log message", example_key="example_value")
    time.sleep(5)

EOF

podman build -t mirror.registry.example.com:5000/python/python-app:latest .
podman push mirror.registry.example.com:5000/python/python-app:latest
```

### Create python-app serive
```bash
oc new-project sample-python-app
oc new-app --name python-app --docker-image mirror.registry.example.com:5000/python/python-app:latest

oc logs python-app-dcb9c57b5-r8vw2
{"message": "This is a structured log message", "timestamp": "2023-12-22T05:27:50.310511", "log_level": "INFO", "user_id": "12345", "example_key": "example_value"}
```
