import os
from celery import Celery
from celery.signals import setup_logging
import logging

# celery broker and backend urls
CELERY_BROKER_URL = os.getenv("REDISSERVER", "redis://redis_server:6379")
CELERY_RESULT_BACKEND = os.getenv("REDISSERVER", "redis://redis_server:6379")


# create celery application
celery_app = Celery(
    "celery",
    backend=CELERY_BROKER_URL,
    broker=CELERY_RESULT_BACKEND,
)
celery_app.conf.update(
    worker_heartbeat=60,  # Adjust this value as needed
    broker_heartbeat=120,  # Adjust this value as needed
    result_expires=60*60*24*365
    # task_soft_time_limit=3600,  # Soft timeout (in seconds)
    # task_time_limit=3700,       # Hard timeout (in seconds)
)
log_path = os.getenv("LOG_PATH", "/var/log/celery")
os.makedirs(log_path, exist_ok=True)
# Setup logging to a file
LOG_FILE = os.getenv("CELERY_LOG_FILE", "celery_worker.log")

@setup_logging.connect
def setup_celery_logging(**kwargs):
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
        handlers=[
            logging.FileHandler(os.path.join(log_path,LOG_FILE)),
            logging.StreamHandler()  # Optional: keep logs in console as well
        ]
    )