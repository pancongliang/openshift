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
