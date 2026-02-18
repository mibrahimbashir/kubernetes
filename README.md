# FastAPI + Redis + Celery + Flower - Async Task Processing

A comprehensive asynchronous task processing system using FastAPI, Redis, Celery, and Flower for monitoring. This project demonstrates how to implement distributed task queues with real-time status updates via REST API and WebSockets.

**🎯 NEW: Kubernetes deployment with autoscaling!** Deploy to production with automatic scaling based on CPU/Memory usage. See [Kubernetes Guide](#kubernetes-deployment-with-autoscaling) below.

## Architecture Overview

```
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│   FastAPI   │────────▶│    Redis    │◀────────│   Celery    │
│  (WebAPI)   │         │  (Broker +  │         │   Workers   │
│             │         │   Backend)  │         │             │
└─────────────┘         └─────────────┘         └─────────────┘
      │                                                 │
      │                                                 │
      ▼                                                 ▼
┌─────────────┐                               ┌─────────────┐
│   Client    │                               │   Flower    │
│ (REST/WS)   │                               │ (Monitor)   │
└─────────────┘                               └─────────────┘
```

### Components

1. **FastAPI (WebAPI)**: REST API server that accepts tasks and provides status endpoints
2. **Redis**: Message broker (task queue) and result backend (task results storage)
3. **Celery Workers**: Background workers that execute tasks asynchronously
4. **Flower**: Web-based monitoring tool for Celery

---

## How Redis is Implemented

### Redis Configuration

Redis serves **dual purposes** in this architecture:

1. **Message Broker**: Queues tasks for Celery workers
2. **Result Backend**: Stores task results and state

#### Connection Setup

**In `app/worker.py` and `celery/worker.py`:**
```python
CELERY_BROKER_URL = os.getenv("REDISSERVER", "redis://redis_server:6379")
CELERY_RESULT_BACKEND = os.getenv("REDISSERVER", "redis://redis_server:6379")

celery_app = Celery(
    "celery",
    backend=CELERY_RESULT_BACKEND,
    broker=CELERY_BROKER_URL,
)
```

**In `app/main.py`:**
```python
redis_client = redis.StrictRedis(host='redis_server', port=6379, db=0)
```

#### Docker Configuration

**In `docker-compose.yml`:**
```yaml
redis_server:
  container_name: redis_server
  image: redis
  volumes:
    - ./SERVER/:/data
  networks:
    - npm-net
```

### What Redis Stores

1. **Task Queue**: Pending tasks waiting to be processed
2. **Task Metadata**: Task state, progress, and results stored with key format `celery-task-meta-{task_id}`
3. **Task Results**: Final output of completed tasks
4. **Task State**: Current status (PENDING, PROGRESS, SUCCESS, FAILURE)

---

## How Celery is Implemented

### Celery Worker Configuration

**Location**: `celery/worker.py` and `app/worker.py`

```python
celery_app = Celery(
    "celery",
    backend=CELERY_BROKER_URL,
    broker=CELERY_RESULT_BACKEND,
)

celery_app.conf.update(
    worker_heartbeat=60,        # Worker heartbeat interval
    broker_heartbeat=120,       # Broker heartbeat interval
    result_expires=60*60*24*365 # Results expire after 1 year
)
```

### Task Definitions

**Location**: `celery/tasks.py`

#### Task 1: Process Task (Simple Demo)

```python
@celery_app.task(name="process.task", bind=True)
def async_process_background_worker(self, name):
    try:
        # Simulate long-running task with progress updates
        for i in range(60):
            sleep(1)
            self.update_state(state="PROGRESS", meta={"done": i, "total": 60})

        return {"result": f"hello {name}"}
    except Exception as ex:
        self.update_state(
            state=states.FAILURE,
            meta={
                "exc_type": type(ex).__name__,
                "exc_message": traceback.format_exc().split("\n"),
            }
        )
        raise ex
```

**Key Features:**
- `bind=True`: Gives access to task instance (`self`)
- `self.update_state()`: Updates task progress in real-time
- Exception handling with detailed error tracking

#### Task 2: File Processing Task (OpenCV Demo)

```python
@celery_app.task(name="fileprocess.task", bind=True)
def async_fileprocess_background_worker(self, new_filename):
    try:
        # Step 1: Read image
        image = cv2.imread("./SERVER/input/"+new_filename)
        self.update_state(state="PROGRESS", meta={"done": 1, "total": 3})

        # Step 2: Process image
        image = cv2.rectangle(image, (0,0), (50,50), (255,255,255), 4)
        self.update_state(state="PROGRESS", meta={"done": 2, "total": 3})

        # Step 3: Save result
        cv2.imwrite(f"./SERVER/output/{new_filename}", image)
        self.update_state(state="PROGRESS", meta={"done": 3, "total": 3})

        return {"result": f"{new_filename}"}
    except Exception as ex:
        # Error handling
        raise ex
```

**Key Features:**
- Multi-step processing with granular progress tracking
- File I/O operations
- Real-time progress updates

### Docker Configuration for Celery

**In `docker-compose.yml`:**
```yaml
worker:
  build:
    dockerfile: DockerfileCelery
    context: .
  container_name: worker
  volumes:
    - ./SERVER/:/celery_tasks/SERVER
    - ./SERVER/:/var/log/celery
  environment:
    REDISSERVER: redis://redis_server:6379
    C_FORCE_ROOT: "true"
    LOG_PATH: "/var/log/celery"
    CELERYD_LOG_FILE: "/var/log/celery/worker.log"
    CELERYD_LOG_LEVEL: "INFO"
  depends_on:
    - redis_server
```

**Key Configuration:**
- `C_FORCE_ROOT`: Allows Celery to run as root (for Docker)
- Logging configuration for debugging
- Volume mounts for shared data and logs

### Scaling Workers

You can scale workers horizontally:

```bash
docker-compose up --scale worker=3
```

This creates 3 worker instances that share the Redis task queue.

---

## FastAPI Integration

### How Tasks are Submitted

**Location**: `app/main.py`

```python
@app.post("/async-process/")
async def async_process(item: Item):
    task_name = "process.task"

    # Send task to Celery via Redis
    task = celery_app.send_task(task_name, args=[item.name])

    return dict(
        task_id=task.id,
        message="Task accepted successfully"
    )
```

**Flow:**
1. FastAPI receives HTTP POST request
2. Task is sent to Celery via `send_task()`
3. Task is queued in Redis
4. Task ID is returned immediately to client
5. Worker picks up task from Redis and executes it

### How Task Status is Checked

```python
@app.get("/task-status/{id}")
def task_status(id: str):
    # Get task result from Redis via Celery
    task = celery_app.AsyncResult(id)

    # Check if task exists in Redis
    task_key = f"celery-task-meta-{id}"
    if not redis_client.exists(task_key):
        raise HTTPException(status_code=404, detail="No task found")

    if task.state == "SUCCESS":
        response = {
            "status": task.state,
            "result": task.result,
            "task_id": id,
        }
    elif task.state == "FAILURE":
        # Fetch detailed error info from Redis
        response = json.loads(
            task.backend.get(
                task.backend.get_key_for_task(task.id)
            ).decode("utf-8")
        )
    else:
        response = {
            "status": task.state,
            "result": task.info,
            "task_id": id,
        }

    return response
```

### Real-Time Updates via WebSocket

```python
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
                # Send error details
                break
            else:
                # Send progress update
                await websocket.send_json({
                    "status": task.state,
                    "result": str(task.info),
                    "task_id": task_id,
                })

            await asyncio.sleep(1)  # Poll every second
    except WebSocketDisconnect:
        print(f"WebSocket disconnected for task: {task_id}")
```

**Key Features:**
- Real-time progress updates every second
- Automatic cleanup on completion or failure
- WebSocket connection management

---

## Flower Monitoring

Flower provides a web-based dashboard to monitor Celery workers and tasks.

**Docker Configuration:**
```yaml
flower:
  container_name: flower
  image: mher/flower
  command: ["celery", "--broker=redis://redis_server:6379", "flower", "--port=5555"]
  ports:
    - "5555:5555"
  environment:
    - FLOWER_BASIC_AUTH=admin:test@123
  depends_on:
    - redis_server
```

**Access Flower:**
- URL: `http://localhost:5555`
- Username: `admin`
- Password: `test@123`

**What Flower Shows:**
- Active workers
- Task execution history
- Task success/failure rates
- Worker resource usage
- Real-time task monitoring

---

## Installation & Setup

### Prerequisites

- Docker
- Docker Compose

### Quick Start

1. **Clone the repository**
   ```bash
   cd Async-FastAPI-Redis-Celery-Flower-master
   ```

2. **Start all services**
   ```bash
   docker-compose up --scale worker=2 --build
   ```

   This starts:
   - FastAPI server on port 80
   - Redis on port 6379 (internal)
   - 2 Celery workers
   - Flower on port 5555

3. **Verify services are running**
   ```bash
   # Check Celery health
   curl http://localhost/health/celery

   # Access Flower dashboard
   open http://localhost:5555
   ```

---

## API Endpoints

### 1. Submit Async Task

**Endpoint**: `POST /async-process/`

**Request:**
```bash
curl -X POST \
  http://localhost/async-process/ \
  -H 'Content-Type: application/json' \
  -d '{"name": "world"}'
```

**Response:**
```json
{
  "task_id": "a86327b8-2d9b-470d-96a9-a27ad87e2c49",
  "message": "Task accepted successfully for processing."
}
```

### 2. Check Task Status

**Endpoint**: `GET /task-status/{task_id}`

**Request:**
```bash
curl http://localhost/task-status/a86327b8-2d9b-470d-96a9-a27ad87e2c49
```

**Response (In Progress):**
```json
{
  "status": "PROGRESS",
  "result": {
    "done": 12,
    "total": 60
  },
  "task_id": "a86327b8-2d9b-470d-96a9-a27ad87e2c49"
}
```

**Response (Success):**
```json
{
  "status": "SUCCESS",
  "result": {
    "result": "hello world"
  },
  "task_id": "a86327b8-2d9b-470d-96a9-a27ad87e2c49"
}
```

**Response (Failure):**
```json
{
  "status": "FAILURE",
  "result": {
    "exc_type": "ZeroDivisionError",
    "exc_message": [
      "Traceback (most recent call last):",
      "  File '/celery_tasks/tasks.py', line 18, in hello_world",
      "    a = a / b",
      "ZeroDivisionError: division by zero"
    ]
  },
  "task_id": "a86327b8-2d9b-470d-96a9-a27ad87e2c49"
}
```

### 3. Submit File Processing Task

**Endpoint**: `POST /async-file`

**Request:**
```bash
curl -X POST \
  http://localhost/async-file \
  -F "uploaded_file=@image.jpg"
```

**Response:**
```json
{
  "task_id": "b72438c9-3e0c-481e-97b0-b38be98f3d5a",
  "input_filename": "image.jpg",
  "new_filename": "2026-01-26_14-30-45-123456.jpg",
  "status": "PROGRESS",
  "message": "Task accepted successfully for processing."
}
```

### 4. Terminate Task

**Endpoint**: `DELETE /terminate-task/{task_id}`

**Request:**
```bash
curl -X DELETE http://localhost/terminate-task/a86327b8-2d9b-470d-96a9-a27ad87e2c49
```

**Response:**
```json
{
  "status": "terminated",
  "task_id": "a86327b8-2d9b-470d-96a9-a27ad87e2c49"
}
```

### 5. Check Celery Health

**Endpoint**: `GET /health/celery`

**Request:**
```bash
curl http://localhost/health/celery
```

**Response:**
```json
{
  "status": "ok",
  "celery": "running",
  "workers": ["celery@worker1", "celery@worker2"],
  "code": 200
}
```

---

## WebSocket Real-Time Updates

### JavaScript Client Example

```javascript
const taskId = "a86327b8-2d9b-470d-96a9-a27ad87e2c49";
const socket = new WebSocket(`ws://localhost/ws/task-status/${taskId}`);

socket.onmessage = (event) => {
    const data = JSON.parse(event.data);
    console.log('Task status:', data.status);
    console.log('Progress:', data.result);

    if (data.status === 'SUCCESS' || data.status === 'FAILURE') {
        socket.close();
    }
};

socket.onerror = (error) => {
    console.error('WebSocket error:', error);
};
```

### Testing with websocat

```bash
# Install websocat
# brew install websocat  # macOS
# apt install websocat   # Linux

# Connect to WebSocket
websocat ws://localhost/ws/task-status/your-task-id
```

---

## Task Lifecycle

```
1. Client sends POST request to FastAPI
           ↓
2. FastAPI creates task and sends to Redis (via celery_app.send_task)
           ↓
3. Redis queues the task
           ↓
4. Celery worker picks task from Redis queue
           ↓
5. Worker executes task and updates state in Redis
           ↓
6. Client polls /task-status/{id} or uses WebSocket
           ↓
7. FastAPI reads task state from Redis (via celery_app.AsyncResult)
           ↓
8. Result returned to client
```

---

## Task States

| State | Description |
|-------|-------------|
| `PENDING` | Task is waiting in queue |
| `PROGRESS` | Task is currently executing |
| `SUCCESS` | Task completed successfully |
| `FAILURE` | Task failed with error |
| `REVOKED` | Task was terminated |

---

## Error Testing

To test error handling:

```bash
curl -X POST \
  http://localhost/async-process/ \
  -H 'Content-Type: application/json' \
  -d '{"name": "error"}'
```

This triggers a `ZeroDivisionError` which is caught and reported via the task status endpoint.

---

## Project Structure

```
.
├── app/
│   ├── main.py           # FastAPI application
│   └── worker.py         # Celery worker configuration
├── celery/
│   ├── tasks.py          # Celery task definitions
│   └── worker.py         # Celery worker configuration
├── static/               # Static files (HTML, CSS, JS)
├── SERVER/               # Shared data directory
│   ├── input/           # Input files
│   └── output/          # Processed files
├── docker-compose.yml    # Docker orchestration
├── DockerfileWebApi      # FastAPI container
├── DockerfileCelery      # Celery worker container
├── requirements_webapi.txt
└── requirements_celery.txt
```

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `REDISSERVER` | Redis connection URL | `redis://redis_server:6379` |
| `C_FORCE_ROOT` | Allow Celery to run as root | `true` |
| `LOG_PATH` | Log file directory | `/var/log/celery` |
| `CELERYD_LOG_FILE` | Worker log file | `/var/log/celery/worker.log` |
| `CELERYD_LOG_LEVEL` | Log level | `INFO` |

---

## Logging

### FastAPI Logs
- Location: `./SERVER/` (mounted volume)
- Configuration: `logging_config.yaml`

### Celery Worker Logs
- Location: `./SERVER/` (mounted volume)
- Files:
  - `worker.log`: Worker process logs
  - `tasks.log`: Task execution logs

### Flower Logs
- Location: `./SERVER/flower.log`

---

## Advanced Configuration

### Celery Worker Options

You can customize worker behavior in `worker.py`:

```python
celery_app.conf.update(
    worker_heartbeat=60,          # Heartbeat interval (seconds)
    broker_heartbeat=120,         # Broker connection heartbeat
    result_expires=60*60*24*365,  # Result expiration (1 year)
    task_soft_time_limit=3600,    # Soft timeout (seconds)
    task_time_limit=3700,         # Hard timeout (seconds)
)
```

### Redis Persistence

Redis data is persisted in `./SERVER/` directory via Docker volume mount.

---

## Troubleshooting

### Workers Not Responding

Check worker health:
```bash
curl http://localhost/health/celery
```

View worker logs:
```bash
docker logs worker
```

### Tasks Stuck in PENDING

1. Check Redis connection
2. Verify workers are running
3. Check Flower dashboard for worker status

### Redis Connection Issues

```bash
# Check Redis container
docker ps | grep redis

# Test Redis connection
docker exec -it redis_server redis-cli ping
```

---

## Production Considerations

1. **Security**:
   - Change default Flower credentials
   - Use environment variables for sensitive data
   - Enable Redis authentication
   - Use HTTPS for FastAPI

2. **Performance**:
   - Scale workers based on load
   - Configure Redis persistence settings
   - Set appropriate task timeouts
   - Monitor memory usage

3. **Reliability**:
   - Implement task retries
   - Set up Redis clustering
   - Use result expiration policies
   - Monitor with Flower

4. **Monitoring**:
   - Set up alerting for worker failures
   - Track task execution times
   - Monitor Redis memory usage
   - Log task errors

---

## Technologies Used

- **FastAPI 0.108.0**: Modern Python web framework
- **Celery 5.3.6**: Distributed task queue
- **Redis 5.0.1**: In-memory data store (broker + backend)
- **Flower**: Celery monitoring tool
- **Uvicorn**: ASGI server
- **Docker & Docker Compose**: Containerization

---

## License

This project is provided as-is for educational purposes.

---

---

## 🚀 Kubernetes Deployment with Autoscaling

### Why Kubernetes?

This project now includes **production-ready Kubernetes manifests** with:
- ✅ **Horizontal Pod Autoscaling** - Automatically scale FastAPI and Celery workers based on CPU/Memory
- ✅ **High Availability** - Multiple replicas with load balancing
- ✅ **Self-Healing** - Automatic pod restart on failures
- ✅ **Resource Management** - CPU/Memory limits and quotas
- ✅ **Zero-Downtime Deployments** - Rolling updates

### Quick Start (5 Minutes)

```bash
# 1. Build and push Docker images
export DOCKER_USERNAME="your-dockerhub-username"
docker build -f DockerfileWebApi -t ${DOCKER_USERNAME}/fastapi-celery:v1 .
docker build -f DockerfileCelery -t ${DOCKER_USERNAME}/celery-worker:v1 .
docker push ${DOCKER_USERNAME}/fastapi-celery:v1
docker push ${DOCKER_USERNAME}/celery-worker:v1

# 2. Update image names in deployment files
sed -i "s|your-docker-registry/fastapi:latest|${DOCKER_USERNAME}/fastapi-celery:v1|g" k8s/03-fastapi-deployment.yaml
sed -i "s|your-docker-registry/celery-worker:latest|${DOCKER_USERNAME}/celery-worker:v1|g" k8s/04-celery-deployment.yaml

# 3. Deploy to Kubernetes
kubectl apply -f k8s/

# 4. Access services
kubectl get svc -n async-tasks
```

**Or use the automated script:**
```bash
chmod +x k8s/deploy.sh
./k8s/deploy.sh local
```

### Autoscaling Configuration

**FastAPI Pods:**
- Min replicas: 2, Max replicas: 10
- Scale up when CPU > 70% or Memory > 80%
- Conservative scale-down (5-minute wait)

**Celery Worker Pods:**
- Min replicas: 2, Max replicas: 20
- Scale up when CPU > 60% or Memory > 75%
- Aggressive scale-up for task bursts

### Testing Autoscaling

```bash
# Run load test script
chmod +x k8s/load-test.sh
./k8s/load-test.sh

# Watch autoscaling in real-time
kubectl get hpa -n async-tasks -w

# Monitor resource usage
kubectl top pods -n async-tasks
```

### Documentation

- **📖 [Complete Kubernetes Guide](KUBERNETES-GUIDE.md)** - Learn Kubernetes concepts from scratch
- **⚡ [Quick Start Guide](k8s/QUICK-START.md)** - Get running in 5 minutes
- **📁 [Manifest Documentation](k8s/README.md)** - Understand each configuration file

### Architecture in Kubernetes

```
┌────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                         │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Namespace: async-tasks                                  │  │
│  │                                                           │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │  │
│  │  │ FastAPI Pods │  │ Worker Pods  │  │  Redis Pod   │  │  │
│  │  │   (2-10)     │  │   (2-20)     │  │     (1)      │  │  │
│  │  │              │  │              │  │              │  │  │
│  │  │  Autoscales  │  │  Autoscales  │  │   Stable     │  │  │
│  │  │  CPU: 70%    │  │  CPU: 60%    │  │              │  │  │
│  │  │  Mem: 80%    │  │  Mem: 75%    │  │              │  │  │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │  │
│  │         │                  │                  │          │  │
│  │         └──────────────────┴──────────────────┘          │  │
│  │                            │                              │  │
│  │                   ┌────────▼────────┐                    │  │
│  │                   │  Shared Storage │                    │  │
│  │                   │      (PVC)      │                    │  │
│  │                   └─────────────────┘                    │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │  HPA (Horizontal Pod Autoscaler)                          │ │
│  │  - Monitors CPU/Memory every 15s                          │ │
│  │  - Scales pods up/down automatically                      │ │
│  └───────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

### Production Deployment

Deploy to cloud providers:

**AWS EKS:**
```bash
eksctl create cluster --name async-tasks-prod --region us-east-1
./k8s/deploy.sh production
```

**Google GKE:**
```bash
gcloud container clusters create async-tasks-prod --num-nodes=3
./k8s/deploy.sh production
```

**Azure AKS:**
```bash
az aks create --resource-group myRG --name async-tasks-prod
./k8s/deploy.sh production
```

---

## Contributing

Feel free to submit issues and enhancement requests.
