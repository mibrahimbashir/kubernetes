import json
from pydantic import BaseModel
from fastapi import FastAPI, UploadFile, File, Request, HTTPException,Response, status
from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from fastapi.openapi.docs import get_swagger_ui_html
from starlette.status import HTTP_401_UNAUTHORIZED
import datetime
import random
from pathlib import Path
from fastapi import WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
import asyncio
from worker import celery_app
import redis
redis_client = redis.StrictRedis(host='redis-service', port=6379, db=0)

# create fast api application
app = FastAPI(docs_url=None, redoc_url=None)  # Disable automatic docs

security = HTTPBasic()

# Configure your credentials
VALID_USERNAME = "admin"
VALID_PASSWORD = "test@123"

def verify_credentials(credentials: HTTPBasicCredentials = Depends(security)):
    correct_username = credentials.username == VALID_USERNAME
    correct_password = credentials.password == VALID_PASSWORD
    if not (correct_username and correct_password):
        raise HTTPException(
            status_code=HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username

@app.get("/docs", include_in_schema=False)
async def get_swagger_documentation(username: str = Depends(verify_credentials)):
    return get_swagger_ui_html(openapi_url="/openapi.json", title="Docs")


# item model
class Item(BaseModel):
    name: str


@app.post("/async-process/")
async def async_process(item: Item):
    # celery task name
    task_name = "process.task"
    
    # send task to celery
    task = celery_app.send_task(task_name, args=[item.name])

    # return task id and url
    return dict(
        task_id=task.id,
        message="Task accepted successfully for processing. Please use the above task_id to track the progress of the task."
    )

@app.post("/async-file")
async def file_async(uploaded_file: UploadFile = File(...)):

    # celery task name
    task_name = "fileprocess.task"

    input_filename = uploaded_file.filename
    new_filename = str(datetime.datetime.now()).replace(" ","_").replace(":","-") + "-" +str(random.randint(100000,999999)) + "." + uploaded_file.filename.split(".")[-1]

    Path("./SERVER/input/").mkdir(parents=True, exist_ok=True)
    file_save_location = f"./SERVER/input/{new_filename}"

    with open(file_save_location, "wb+") as file_object:
        file_object.write(uploaded_file.file.read())

    task = celery_app.send_task(task_name, args=[new_filename])

    return dict(
        task_id=task.id,
        input_filename = input_filename, 
        new_filename = new_filename, 
        status = "PROGRESS", 
        message="Task accepted successfully for processing. Please use the above task_id to track the progress of the task."
    )


@app.get("/task-status/{id}")
def task_status(id: str):
    # get celery task from id
    task = celery_app.AsyncResult(id)
    task_key = f"celery-task-meta-{id}"  # Default key format for Celery results in Redis
    if not redis_client.exists(task_key):
        raise HTTPException(status_code=404, detail="No task with the given UUID found")

    # if task is in success state
    if task.state == "SUCCESS":
        response = {
            "status": task.state,
            "result": task.result,
            "task_id": id,
        }

    # if task is in failure state
    elif task.state == "FAILURE":
        response = json.loads(
            task.backend.get(
                task.backend.get_key_for_task(task.id),
            ).decode("utf-8")
        )
        del response["children"]
        del response["traceback"]

    # if task is in other state
    else:
        response = {
            "status": task.state,
            "result": task.info,
            "task_id": id,
        }

    # return response
    return response

@app.delete("/terminate-task/{id}")
def terminate_task(id: str):
    task = celery_app.AsyncResult(id)

    if task.state in ["SUCCESS", "FAILURE"]:
        raise HTTPException(status_code=400, detail="Task already completed or failed, cannot terminate.")

    # Revoke the task
    task.revoke(terminate=True)

    return {"status": "terminated", "task_id": id}

@app.options("/health/celery")
@app.head("/health/celery")
@app.get("/health/celery")
def check_celery(response: Response):
    try:
        insp = celery_app.control.inspect(timeout=5)
        ping_result = insp.ping()
        print(ping_result)

        # ping_result example:
        # {'celery@worker1': {'ok': 'pong'}}

        if ping_result:
            response.status_code = status.HTTP_200_OK
            return {
                "status": "ok",
                "celery": "running",
                "workers": list(ping_result.keys()),
                "code": 200,
            }

        response.status_code = status.HTTP_400_BAD_REQUEST
        return {
            "status": "error",
            "celery": "no workers responding",
            "code": 400,
        }

    except Exception as e:
        response.status_code = status.HTTP_400_BAD_REQUEST
        return {
            "status": "error",
            "celery": "unreachable",
            "detail": str(e),
            "code": 400,
        }

@app.websocket("/ws/task-status/{task_id}")
async def websocket_task_status(websocket: WebSocket, task_id: str):
    await websocket.accept()

    try:
        while True:
            task = celery_app.AsyncResult(task_id)

            if task.state == "SUCCESS":
                await websocket.send_json({
                    "status": task.state,
                    "result": task.result,
                    "task_id": task_id,
                })
                break

            elif task.state == "FAILURE":
                response = json.loads(
                    task.backend.get(
                        task.backend.get_key_for_task(task.id),
                    ).decode("utf-8")
                )
                del response["children"]
                del response["traceback"]
                response["task_id"] = task_id
                await websocket.send_json(response)
                break

            else:
                await websocket.send_json({
                    "status": task.state,
                    "result": str(task.info),
                    "task_id": task_id,
                })

            await asyncio.sleep(1)  # Poll every second

    except WebSocketDisconnect:
        print(f"WebSocket disconnected for task: {task_id}")

# Add this ABOVE the app.mount line
@app.get("/health")
def health():
    return {"status": "ok", "message": "API is running"}

# This must stay last
app.mount("/", StaticFiles(directory="static"), name="static")
