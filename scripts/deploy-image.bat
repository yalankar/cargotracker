@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM deploy-image.bat - Deploy to Azure AKS
REM Eclipse Cargo Tracker - Jakarta EE Application
REM ============================================================

set "APP_NAME=cargo-tracker"
set "NAMESPACE=cargo-tracker"
set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%.."
set "K8S_DIR=%PROJECT_ROOT%\kubernetes"

echo ============================================================
echo   Deploy to Azure AKS - Eclipse Cargo Tracker
echo ============================================================
echo.

REM ---- Prompt for Azure details ----
set /p "RESOURCE_GROUP=Enter Azure Resource Group name: "
if "!RESOURCE_GROUP!"=="" (
    echo ERROR: Resource group cannot be empty.
    exit /b 1
)

set /p "CLUSTER_NAME=Enter AKS Cluster name: "
if "!CLUSTER_NAME!"=="" (
    echo ERROR: AKS cluster name cannot be empty.
    exit /b 1
)

set /p "IMAGE_URI=Enter full Docker image URI (e.g., myregistry.azurecr.io/cargo-tracker:latest): "
if "!IMAGE_URI!"=="" (
    echo ERROR: Image URI cannot be empty.
    exit /b 1
)

REM ---- Prompt for application-specific environment variables ----
echo.
echo ---- Application Configuration ----
echo Press Enter to skip optional values and use defaults.
echo.

set /p "GRAPH_TRAVERSAL_URL_INPUT=Enter GRAPH_TRAVERSAL_URL [http://localhost:8080/rest/graph-traversal/shortest-path]: "
if "!GRAPH_TRAVERSAL_URL_INPUT!"=="" (
    set "GRAPH_TRAVERSAL_URL=http://localhost:8080/rest/graph-traversal/shortest-path"
) else (
    set "GRAPH_TRAVERSAL_URL=!GRAPH_TRAVERSAL_URL_INPUT!"
)

REM ---- Configure kubectl for AKS ----
echo.
echo Configuring kubectl for AKS cluster: !CLUSTER_NAME! in resource group: !RESOURCE_GROUP!
az aks get-credentials --resource-group "!RESOURCE_GROUP!" --name "!CLUSTER_NAME!" --overwrite-existing
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to get AKS credentials.
    exit /b 1
)

echo.
echo Verifying cluster connectivity...
kubectl cluster-info
if !ERRORLEVEL! neq 0 (
    echo ERROR: Cannot connect to AKS cluster.
    exit /b 1
)

REM ---- Create temp directory for manifests ----
set "DEPLOY_DIR=%TEMP%\cargo-tracker-deploy-%RANDOM%"
mkdir "!DEPLOY_DIR!"
xcopy /E /I /Q "!K8S_DIR!" "!DEPLOY_DIR!" >nul

REM ---- Replace placeholders using PowerShell ----
echo.
echo Replacing placeholders in manifests...

powershell -NoProfile -Command ^
    "(Get-Content '!DEPLOY_DIR!\deployment.yaml') -replace '\{\{IMAGE_URI\}\}', '!IMAGE_URI!' -replace '\{\{GRAPH_TRAVERSAL_URL\}\}', '!GRAPH_TRAVERSAL_URL!' -replace '\{\{NAMESPACE\}\}', '!NAMESPACE!' | Set-Content '!DEPLOY_DIR!\deployment.yaml'"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to update deployment.yaml.
    exit /b 1
)

powershell -NoProfile -Command ^
    "(Get-Content '!DEPLOY_DIR!\service.yaml') -replace '\{\{NAMESPACE\}\}', '!NAMESPACE!' | Set-Content '!DEPLOY_DIR!\service.yaml'"

powershell -NoProfile -Command ^
    "(Get-Content '!DEPLOY_DIR!\ingress.yaml') -replace '\{\{NAMESPACE\}\}', '!NAMESPACE!' | Set-Content '!DEPLOY_DIR!\ingress.yaml'"

REM ---- Apply Kubernetes manifests ----
echo.
echo Applying Kubernetes manifests...

echo   [1/4] Applying namespace...
kubectl apply -f "!DEPLOY_DIR!\namespace.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply namespace.yaml.
    exit /b 1
)

echo   [2/4] Applying deployment...
kubectl apply -f "!DEPLOY_DIR!\deployment.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply deployment.yaml.
    exit /b 1
)

echo   [3/4] Applying service...
kubectl apply -f "!DEPLOY_DIR!\service.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply service.yaml.
    exit /b 1
)

echo   [4/4] Applying ingress...
kubectl apply -f "!DEPLOY_DIR!\ingress.yaml"
if !ERRORLEVEL! neq 0 (
    echo ERROR: Failed to apply ingress.yaml.
    exit /b 1
)

REM ---- Wait for rollout ----
echo.
echo Waiting for deployment rollout to complete...
kubectl rollout status deployment/!APP_NAME! -n !NAMESPACE! --timeout=300s
if !ERRORLEVEL! neq 0 (
    echo ERROR: Deployment rollout failed or timed out.
    echo Rollback command: kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!
    exit /b 1
)

REM ---- Verify resources ----
echo.
echo Verifying deployed resources...
kubectl get pods,svc,ingress -n !NAMESPACE!

echo.
echo ============================================================
echo   Deployment completed successfully!
echo.
echo   Namespace:  !NAMESPACE!
echo   Image:      !IMAGE_URI!
echo ============================================================
echo.
echo Rollback command (if needed):
echo   kubectl rollout undo deployment/!APP_NAME! -n !NAMESPACE!

REM ---- Cleanup temp dir ----
rmdir /S /Q "!DEPLOY_DIR!" 2>nul

endlocal
