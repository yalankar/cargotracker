# Eclipse Cargo Tracker - Deployment Guide

## Overview

This guide covers building, containerizing, and deploying the **Eclipse Cargo Tracker** application to **Azure Kubernetes Service (AKS)**. The application is a Jakarta EE 10 web application running on Payara Micro, demonstrating Domain-Driven Design (DDD) principles.

- **Technology Stack**: Jakarta EE 10, Java 11, Payara Micro
- **Build Tool**: Maven 3.9.x
- **Packaging**: WAR
- **Runtime Image**: `mcr.microsoft.com/openjdk/jdk:11-ubuntu`
- **Application Port**: 8080
- **Context Root**: `/` (deployed as root context)

---

## Prerequisites

### Local Development
- Java 11 (JDK)
- Maven 3.9.x
- Docker Desktop (or Docker Engine)
- Git

### Azure AKS Deployment
- Azure CLI (`az`) - [Install Guide](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- `kubectl` - [Install Guide](https://kubernetes.io/docs/tasks/tools/)
- Azure Subscription with:
  - Azure Container Registry (ACR) or Docker Hub account
  - Azure Kubernetes Service (AKS) cluster
  - Azure Application Gateway Ingress Controller (AGIC) enabled on AKS

---

## Project Structure

```
CAUC3CMP/
├── Dockerfile                    # Multi-stage Docker build
├── docker-compose.yml            # Local development compose file
├── .dockerignore                 # Docker build exclusions
├── pom.xml                       # Maven build configuration
├── src/
│   ├── main/
│   │   ├── java/                 # Application source code
│   │   ├── resources/            # Persistence, batch job configs
│   │   └── webapp/               # JSF web application (xhtml, WEB-INF)
│   └── test/                     # Test sources
├── kubernetes/
│   ├── namespace.yaml            # Kubernetes namespace
│   ├── deployment.yaml           # Application deployment
│   ├── service.yaml              # ClusterIP service
│   └── ingress.yaml              # Azure Application Gateway ingress
├── scripts/
│   ├── build-push.sh             # Linux/macOS build & push script
│   ├── build-push.bat            # Windows build & push script
│   ├── deploy-image.sh           # Linux/macOS AKS deploy script
│   └── deploy-image.bat          # Windows AKS deploy script
└── docs/
    └── DEPLOYMENT.md             # This file
```

---

## Local Development Setup

### 1. Build the Application Locally

```bash
# Build with embedded H2 database (default Payara profile)
mvn clean package -Ppayara -DskipTests

# Build with PostgreSQL (cloud profile)
mvn clean package -Pcloud \
  -DpostgreSqlJdbcUrl="jdbc:postgresql://localhost:5432/cargotracker" \
  -DpostgreSqlUsername="postgres" \
  -DpostgreSqlPassword="postgres"
```

### 2. Run with Docker Compose

```bash
# Build and start the application container
docker compose up --build

# Run in detached mode
docker compose up -d --build

# View logs
docker compose logs -f cargo-tracker

# Stop the application
docker compose down
```

The application will be available at: **http://localhost:8080**

### 3. Run Locally with Payara Micro (without Docker)

```bash
# Download Payara Micro and run
java -jar payara-micro.jar --deploy target/cargo-tracker.war --contextroot / --port 8080
```

---

## Docker Build

### Build the Docker Image Manually

```bash
# Build from project root
docker build -t cargo-tracker:latest .

# Build with a specific tag
docker build -t cargo-tracker:v3.1 .

# Verify the image
docker images | grep cargo-tracker
```

### Run the Docker Container

```bash
docker run -d \
  --name cargo-tracker \
  -p 8080:8080 \
  -e JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport" \
  -e TZ=UTC \
  cargo-tracker:latest
```

---

## Build and Push to Registry

Use the provided scripts to build and push the Docker image to your registry.

### Linux/macOS

```bash
# Make the script executable
chmod +x scripts/build-push.sh

# Run from project root
./scripts/build-push.sh
```

### Windows

```cmd
scripts\build-push.bat
```

The script will prompt you to:
1. Select registry type (Azure ACR or Docker Hub)
2. Enter registry credentials
3. Specify an image tag (defaults to `latest`)

---

## Azure AKS Deployment

### Step 1: Prerequisites Setup

```bash
# Login to Azure
az login

# Set your subscription
az account set --subscription "<your-subscription-id>"

# Verify AKS cluster access
az aks list --output table
```

### Step 2: Configure ACR (if using Azure Container Registry)

```bash
# Create ACR (if not exists)
az acr create --resource-group <resource-group> --name <acr-name> --sku Basic

# Attach ACR to AKS cluster (allows AKS to pull images)
az aks update --resource-group <resource-group> --name <aks-cluster> \
  --attach-acr <acr-name>
```

### Step 3: Build and Push the Image

```bash
chmod +x scripts/build-push.sh
./scripts/build-push.sh
# Select option 1 (Azure ACR) and follow prompts
```

### Step 4: Deploy to AKS

```bash
chmod +x scripts/deploy-image.sh
./scripts/deploy-image.sh
```

The deploy script will:
1. Prompt for Azure Resource Group and AKS cluster name
2. Prompt for the full Docker image URI
3. Prompt for optional environment variable overrides
4. Configure `kubectl` with AKS credentials
5. Apply Kubernetes manifests in order (namespace → deployment → service → ingress)
6. Wait for the deployment rollout to complete
7. Display the application URL

### Step 5: Verify Deployment

```bash
# Check all resources in the namespace
kubectl get all -n cargo-tracker

# Check pod status
kubectl get pods -n cargo-tracker

# View pod logs
kubectl logs -l app=cargo-tracker -n cargo-tracker --tail=100

# Describe a pod for troubleshooting
kubectl describe pod -l app=cargo-tracker -n cargo-tracker
```

### Step 6: Access the Application

```bash
# Get ingress details
kubectl get ingress -n cargo-tracker

# Get the external IP (if using LoadBalancer)
kubectl get svc -n cargo-tracker
```

The application will be accessible at the host configured in `kubernetes/ingress.yaml` (default: `http://cargo-tracker.example.com`).

> **Note**: Update the `host` field in `kubernetes/ingress.yaml` to match your actual domain name before deploying.

---

## Kubernetes Manifest Details

### namespace.yaml
Creates the `cargo-tracker` namespace to isolate all application resources.

### deployment.yaml
- **Replicas**: 2 (for high availability)
- **Image**: Pulled from `{{IMAGE_URI}}` (replaced at deploy time)
- **Resources**: 
  - Requests: 250m CPU, 512Mi memory
  - Limits: 500m CPU, 1Gi memory
- **Liveness Probe**: TCP socket check on port 8080 (after 90s initial delay)
- **Readiness Probe**: HTTP GET `/cargo-tracker/` on port 8080 (after 60s initial delay)
- **JVM Options**: Container-aware memory settings with 75% RAM allocation

### service.yaml
- **Type**: ClusterIP (internal cluster access)
- **Port**: 80 → 8080 (container port)

### ingress.yaml
- **Ingress Class**: `azure/application-gateway` (Azure AGIC)
- **Cookie-based affinity**: Enabled for session stickiness (Jakarta EE sessions)
- **Host**: `cargo-tracker.example.com` (update to your domain)

---

## Configuration Management

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `JAVA_OPTS` | `-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0` | JVM options |
| `TZ` | `UTC` | Timezone |
| `LANG` | `en_US.UTF-8` | Locale |
| `GRAPH_TRAVERSAL_URL` | `http://localhost:8080/rest/graph-traversal/shortest-path` | Pathfinder service URL |

### Database Configuration

The application uses **H2 embedded database** by default (suitable for development/demo). For production, configure PostgreSQL:

```yaml
# In kubernetes/deployment.yaml, uncomment and configure:
env:
  - name: DB_DRIVER_CLASS
    value: "org.postgresql.ds.PGPoolingDataSource"
  - name: DB_JDBC_URL
    value: "jdbc:postgresql://<host>:5432/<database>"
  - name: DB_USER
    value: "<username>"
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: cargo-tracker-db-secret
        key: password
```

Create a Kubernetes secret for the database password:
```bash
kubectl create secret generic cargo-tracker-db-secret \
  --from-literal=password=<your-password> \
  -n cargo-tracker
```

---

## Scaling and Management

### Manual Scaling

```bash
# Scale to 3 replicas
kubectl scale deployment cargo-tracker --replicas=3 -n cargo-tracker

# Scale back to 2
kubectl scale deployment cargo-tracker --replicas=2 -n cargo-tracker
```

### Horizontal Pod Autoscaler (HPA)

```bash
# Create HPA (scale between 2-10 pods based on CPU)
kubectl autoscale deployment cargo-tracker \
  --cpu-percent=70 \
  --min=2 \
  --max=10 \
  -n cargo-tracker

# Check HPA status
kubectl get hpa -n cargo-tracker
```

### Rolling Updates

```bash
# Update the image
kubectl set image deployment/cargo-tracker \
  cargo-tracker=<new-image-uri> \
  -n cargo-tracker

# Monitor rollout
kubectl rollout status deployment/cargo-tracker -n cargo-tracker
```

### Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/cargo-tracker -n cargo-tracker

# Rollback to a specific revision
kubectl rollout history deployment/cargo-tracker -n cargo-tracker
kubectl rollout undo deployment/cargo-tracker --to-revision=<revision> -n cargo-tracker
```

---

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod -l app=cargo-tracker -n cargo-tracker

# Check pod logs
kubectl logs -l app=cargo-tracker -n cargo-tracker --previous

# Check resource constraints
kubectl top pods -n cargo-tracker
```

### Application Not Accessible

```bash
# Check service endpoints
kubectl get endpoints -n cargo-tracker

# Check ingress status
kubectl describe ingress cargo-tracker-ingress -n cargo-tracker

# Test internal connectivity
kubectl run test-pod --image=busybox --rm -it --restart=Never -n cargo-tracker -- \
  wget -qO- http://cargo-tracker-service/
```

### JVM Memory Issues

If pods are OOMKilled, increase memory limits in `kubernetes/deployment.yaml`:
```yaml
resources:
  requests:
    memory: "1Gi"
  limits:
    memory: "2Gi"
```
Also update `JAVA_OPTS`:
```yaml
- name: JAVA_OPTS
  value: "-Xmx1g -Xms512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
```

### Payara Micro Startup Issues

Payara Micro requires sufficient time to start (60-90 seconds). If readiness probes fail:
```yaml
readinessProbe:
  initialDelaySeconds: 90   # Increase if needed
  periodSeconds: 15
  failureThreshold: 10      # Allow more retries
```

### Image Pull Errors

```bash
# Verify ACR is attached to AKS
az aks check-acr --resource-group <rg> --name <aks-cluster> --acr <acr-name>

# Re-attach ACR if needed
az aks update --resource-group <rg> --name <aks-cluster> --attach-acr <acr-name>
```

---

## Security Considerations

1. **Non-root user**: The container runs as a non-root user (`payara`, UID 1000)
2. **Read-only filesystem**: Consider adding `readOnlyRootFilesystem: true` with appropriate volume mounts
3. **Network policies**: Implement Kubernetes NetworkPolicies to restrict pod-to-pod communication
4. **Secrets management**: Use Azure Key Vault with the Secrets Store CSI Driver for sensitive configuration
5. **Image scanning**: Enable Azure Defender for Containers to scan images in ACR
6. **RBAC**: Apply least-privilege RBAC policies for the application's service account
7. **TLS**: Configure TLS termination at the Application Gateway level for HTTPS

---

## Jakarta EE / Payara Micro Notes

- **Session Affinity**: The ingress is configured with cookie-based affinity to ensure HTTP sessions are routed to the same pod (important for JSF stateful views)
- **JMS Queues**: The application uses JMS queues (CargoHandledQueue, MisdirectedCargoQueue, etc.) which are provided by the embedded Payara Micro JMS broker
- **JPA/H2**: The embedded H2 database stores data in `/opt/payara/cargo-tracker-data/` - this is mapped to an `emptyDir` volume (data is lost on pod restart). For persistence, use a PersistentVolumeClaim or external PostgreSQL
- **Context Root**: The application is deployed at the root context `/` (not `/cargo-tracker`)
- **Jakarta Faces**: The application uses Jakarta Faces (JSF) with PrimeFaces components

---

## Support

For issues related to the Eclipse Cargo Tracker application:
- GitHub Issues: https://github.com/eclipse-ee4j/cargotracker/issues
- Documentation: https://eclipse-ee4j.github.io/cargotracker/
