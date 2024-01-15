# app.py
import logging
import json
import time
from datetime import datetime

class StructuredMessage(object):
    def __init__(self, message, **kwargs):
        self.message = message
        self.kwargs = kwargs

    def to_json_pretty(self):
        return json.dumps({
            '@timestamp': datetime.now().isoformat(),
            '@version': '1',
            'message': self.message,
            'logger_name': 'my.company.multilinelog.service.GreetingController',
            'thread_name': 'main',
            'level': 'INFO',
            'level_value': 20000,
            **self.kwargs
        }, indent=4)

def setup_logging():
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    handler = logging.StreamHandler()
    formatter = logging.Formatter('%(message)s')
    handler.setFormatter(formatter)
    logger.addHandler(handler)

def log_structured_message(message, **kwargs):
    logging.info(StructuredMessage(message, **kwargs).to_json_pretty())

setup_logging()

while True:
    log_structured_message("Init GreetingController with message:\nHello User from application.yaml!", extra_key="extra_value")
    time.sleep(5)
