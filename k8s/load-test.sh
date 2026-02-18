#!/bin/bash
# =============================================================================
# Load Testing Script - Test Autoscaling
# =============================================================================
# This script generates load to test Kubernetes autoscaling
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}==============================================================================${NC}"
echo -e "${GREEN}Load Testing Script - Testing Kubernetes Autoscaling${NC}"
echo -e "${GREEN}==============================================================================${NC}"

# Get FastAPI URL
echo -e "\n${YELLOW}Getting FastAPI service URL...${NC}"

if command -v minikube &>/dev/null; then
    FASTAPI_URL=$(minikube service fastapi-service -n async-tasks --url 2>/dev/null | head -n 1)
else
    FASTAPI_IP=$(kubectl get svc fastapi-service -n async-tasks -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    FASTAPI_URL="http://${FASTAPI_IP}"
fi

echo -e "${GREEN}FastAPI URL: ${FASTAPI_URL}${NC}"

# Check if service is accessible
if ! curl -s -o /dev/null -w "%{http_code}" "${FASTAPI_URL}/health/celery" | grep -q "200"; then
    echo -e "${RED}ERROR: FastAPI service not accessible at ${FASTAPI_URL}${NC}"
    echo -e "${YELLOW}Make sure the deployment is complete and services are running${NC}"
    exit 1
fi

echo -e "${GREEN}✓ FastAPI service is accessible${NC}"

# Menu
echo -e "\n${YELLOW}Select load test type:${NC}"
echo "1) API Load Test (test FastAPI autoscaling)"
echo "2) Worker Load Test (test Celery worker autoscaling)"
echo "3) Combined Load Test (both API and workers)"
echo "4) Continuous Load (run until stopped)"

read -p "Enter choice [1-4]: " choice

# Function to run API load test
api_load_test() {
    local duration=$1
    local concurrency=$2

    echo -e "\n${GREEN}==============================================================================${NC}"
    echo -e "${GREEN}Running API Load Test${NC}"
    echo -e "${GREEN}Duration: ${duration}s | Concurrency: ${concurrency}${NC}"
    echo -e "${GREEN}==============================================================================${NC}"

    # Open HPA monitoring in background
    echo -e "${YELLOW}Opening HPA monitor (watch in another terminal)...${NC}"
    gnome-terminal -- bash -c "kubectl get hpa -n async-tasks -w" 2>/dev/null || \
    xterm -e "kubectl get hpa -n async-tasks -w" 2>/dev/null || \
    echo -e "${YELLOW}Monitor HPA manually with: kubectl get hpa -n async-tasks -w${NC}"

    # Check if hey is installed
    if command -v hey &>/dev/null; then
        echo -e "${GREEN}Using 'hey' for load testing...${NC}"
        hey -c ${concurrency} -z ${duration}s -m POST \
            -H "Content-Type: application/json" \
            -d '{"name":"loadtest"}' \
            "${FASTAPI_URL}/async-process/"
    elif command -v ab &>/dev/null; then
        echo -e "${GREEN}Using 'ab' (Apache Bench) for load testing...${NC}"
        # Calculate number of requests (duration * 10 requests/sec * concurrency)
        total_requests=$((duration * 10 * concurrency))
        ab -n ${total_requests} -c ${concurrency} \
            -p <(echo '{"name":"loadtest"}') \
            -T "application/json" \
            "${FASTAPI_URL}/async-process/"
    else
        echo -e "${YELLOW}Neither 'hey' nor 'ab' found. Using curl loop...${NC}"
        for i in $(seq 1 ${duration}); do
            for j in $(seq 1 ${concurrency}); do
                curl -X POST "${FASTAPI_URL}/async-process/" \
                    -H "Content-Type: application/json" \
                    -d '{"name":"loadtest"}' &
            done
            wait
            echo -e "${YELLOW}Completed ${i}/${duration} seconds${NC}"
        done
    fi

    echo -e "\n${GREEN}API Load Test Complete!${NC}"
}

# Function to run worker load test
worker_load_test() {
    local num_tasks=$1

    echo -e "\n${GREEN}==============================================================================${NC}"
    echo -e "${GREEN}Running Worker Load Test${NC}"
    echo -e "${GREEN}Number of tasks: ${num_tasks}${NC}"
    echo -e "${GREEN}==============================================================================${NC}"

    # Check if test image exists
    if [ ! -f "test-image.jpg" ]; then
        echo -e "${YELLOW}Creating test image...${NC}"
        # Create a simple test image using ImageMagick or download one
        if command -v convert &>/dev/null; then
            convert -size 800x600 xc:blue test-image.jpg
        else
            echo -e "${YELLOW}Downloading test image...${NC}"
            curl -o test-image.jpg https://via.placeholder.com/800x600.jpg
        fi
    fi

    echo -e "${GREEN}Submitting ${num_tasks} file processing tasks...${NC}"

    for i in $(seq 1 ${num_tasks}); do
        curl -X POST "${FASTAPI_URL}/async-file" \
            -F "uploaded_file=@test-image.jpg" \
            -s -o /dev/null &

        if [ $((i % 10)) -eq 0 ]; then
            echo -e "${YELLOW}Submitted ${i}/${num_tasks} tasks${NC}"
            wait
        fi
    done

    wait
    echo -e "\n${GREEN}Worker Load Test Complete!${NC}"
    echo -e "${YELLOW}Monitor workers with: kubectl get hpa celery-worker-hpa -n async-tasks -w${NC}"
}

# Execute based on choice
case $choice in
    1)
        echo -e "\n${YELLOW}API Load Test Configuration:${NC}"
        read -p "Duration in seconds [default: 120]: " duration
        duration=${duration:-120}
        read -p "Concurrent requests [default: 50]: " concurrency
        concurrency=${concurrency:-50}

        api_load_test $duration $concurrency
        ;;
    2)
        echo -e "\n${YELLOW}Worker Load Test Configuration:${NC}"
        read -p "Number of tasks to submit [default: 100]: " num_tasks
        num_tasks=${num_tasks:-100}

        worker_load_test $num_tasks
        ;;
    3)
        echo -e "\n${YELLOW}Combined Load Test${NC}"
        echo -e "${GREEN}Running API load test first...${NC}"
        api_load_test 60 30

        echo -e "\n${GREEN}Now running worker load test...${NC}"
        worker_load_test 50
        ;;
    4)
        echo -e "\n${YELLOW}Continuous Load Test (Ctrl+C to stop)${NC}"
        echo -e "${GREEN}Generating continuous load...${NC}"

        while true; do
            for i in {1..10}; do
                curl -X POST "${FASTAPI_URL}/async-process/" \
                    -H "Content-Type: application/json" \
                    -d '{"name":"continuous"}' \
                    -s -o /dev/null &
            done
            sleep 1
        done
        ;;
    *)
        echo -e "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

# Show current status
echo -e "\n${GREEN}==============================================================================${NC}"
echo -e "${GREEN}Current Cluster Status${NC}"
echo -e "${GREEN}==============================================================================${NC}"

echo -e "\n${YELLOW}Pods:${NC}"
kubectl get pods -n async-tasks

echo -e "\n${YELLOW}HPA Status:${NC}"
kubectl get hpa -n async-tasks

echo -e "\n${YELLOW}Resource Usage:${NC}"
kubectl top pods -n async-tasks 2>/dev/null || echo "Metrics not available yet (wait 1-2 minutes)"

echo -e "\n${GREEN}==============================================================================${NC}"
echo -e "${GREEN}Load Test Complete!${NC}"
echo -e "${GREEN}==============================================================================${NC}"

echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "  1. Watch autoscaling: kubectl get hpa -n async-tasks -w"
echo -e "  2. View pod metrics: kubectl top pods -n async-tasks"
echo -e "  3. Check Flower dashboard for task statistics"
echo -e "  4. View scaling events: kubectl get events -n async-tasks --sort-by='.lastTimestamp'"
