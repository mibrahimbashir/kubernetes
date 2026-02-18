import traceback
from time import sleep
from celery import states

from worker import celery_app
import cv2
from pathlib import Path
import time


# create celery worker for 'hello.task' task
@celery_app.task(name="process.task", bind=True)
def async_process_background_worker(self, name):
    try:
        # if name is error
        if name == "error":
            # will raise ZeroDivisionError
            a, b = 1, 0
            a = a / b

        # update task state every 1 second
        for i in range(60):
            sleep(1)
            self.update_state(state="PROGRESS", meta={"done": i, "total": 60})

        # return result
        return {"result": f"hello {name}"}

    # if any error occurs
    except Exception as ex:
        # update task state to failure
        self.update_state(
            state=states.FAILURE,
            meta={
                "exc_type": type(ex).__name__,
                "exc_message": traceback.format_exc().split("\n"),
            },
        )

        # raise exception
        raise ex


@celery_app.task(name="fileprocess.task", bind=True)
def async_fileprocess_background_worker(self, new_filename):
    try:

        image = cv2.imread("./SERVER/input/"+new_filename)
        self.update_state(state="PROGRESS", meta={"done": 1, "total": 3})
        time.sleep(5)

        image = cv2.rectangle(image, (0,0), (50,50), (255,255,255), 4)
        self.update_state(state="PROGRESS", meta={"done": 2, "total": 3})
        time.sleep(5)

        Path("./SERVER/output/").mkdir(parents=True, exist_ok=True)
        cv2.imwrite(f"./SERVER/output/{new_filename}", image)
        self.update_state(state="PROGRESS", meta={"done": 3, "total": 3})
        time.sleep(5)
            

        # return result
        return {"result": f"{new_filename}"}

    # if any error occurs
    except Exception as ex:
        # update task state to failure
        self.update_state(
            state=states.FAILURE,
            meta={
                "exc_type": type(ex).__name__,
                "exc_message": traceback.format_exc().split("\n"),
            },
        )

        # raise exception
        raise ex
