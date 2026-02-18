@echo off
REM =============================================================================
REM Windows Deployment Script for Kubernetes
REM =============================================================================
REM Usage: deploy-windows.bat

echo ===============================================================================
echo Deploying FastAPI + Celery + Redis to Kubernetes (Windows)
echo ===============================================================================

REM Check if kubectl exists
where kubectl >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: kubectl not found. Please install kubectl first.
    exit /b 1
)

REM Check cluster connectivity
kubectl cluster-info >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Cannot connect to Kubernetes cluster.
    echo For Docker Desktop: Enable Kubernetes in settings
    echo For Minikube: Run 'minikube start'
    exit /b 1
)

echo [1/4] Kubernetes cluster accessible
echo.

REM Apply manifests
echo [2/4] Applying Kubernetes manifests...
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-configmap.yaml
kubectl apply -f k8s/06-persistent-volume.yaml
kubectl apply -f k8s/02-redis-deployment.yaml
kubectl apply -f k8s/03-fastapi-deployment.yaml
kubectl apply -f k8s/04-celery-deployment.yaml
kubectl apply -f k8s/05-flower-deployment.yaml
kubectl apply -f k8s/07-hpa-fastapi.yaml
kubectl apply -f k8s/08-hpa-celery.yaml
kubectl apply -f k8s/09-resource-quota.yaml

echo.
echo [3/4] Waiting for pods to be ready...
timeout /t 10 /nobreak >nul

REM Show status
echo.
echo [4/4] Deployment Status:
echo.
echo Pods:
kubectl get pods -n async-tasks

echo.
echo Services:
kubectl get svc -n async-tasks

echo.
echo HPA:
kubectl get hpa -n async-tasks

echo.
echo ===============================================================================
echo Deployment Complete!
echo ===============================================================================
echo.
echo Access your services:
echo   kubectl get svc -n async-tasks
echo.
echo Useful commands:
echo   kubectl get pods -n async-tasks
echo   kubectl logs -f ^<pod-name^> -n async-tasks
echo   kubectl port-forward svc/flower-service -n async-tasks 5555:5555
echo.

pause
