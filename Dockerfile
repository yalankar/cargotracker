# ============================================================
# Stage 1: Build Stage
# ============================================================
FROM maven:3.9.4-eclipse-temurin-11 AS builder

WORKDIR /workspace

# Copy pom.xml first for dependency caching
COPY pom.xml .

# Download dependencies (cached layer)
RUN mvn dependency:go-offline -Ppayara -DskipTests --batch-mode

# Copy source code
COPY src ./src

# Build the WAR artifact using the payara profile
RUN mvn clean package -Ppayara -DskipTests --batch-mode

# ============================================================
# Stage 2: Runtime Stage
# ============================================================
FROM mcr.microsoft.com/openjdk/jdk:11-ubuntu

WORKDIR /opt/payara

# Create non-root user for security
RUN groupadd -r payara && useradd -r -g payara -d /opt/payara -s /bin/bash payara \
    && chown -R payara:payara /opt/payara

# Download Payara Micro
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && java -version

# Copy Payara Micro JAR from Maven local repository in builder stage
COPY --from=builder /root/.m2/repository/fish/payara/extras/payara-micro /tmp/payara-micro-repo/
RUN find /tmp/payara-micro-repo -name "payara-micro-*.jar" ! -name "*sources*" ! -name "*javadoc*" \
        -exec cp {} /opt/payara/payara-micro.jar \; \
    && rm -rf /tmp/payara-micro-repo

# Copy the built WAR artifact
COPY --from=builder /workspace/target/cargo-tracker.war /opt/payara/deployments/cargo-tracker.war

# Set ownership
RUN chown -R payara:payara /opt/payara

# Switch to non-root user
USER payara

# Application port
EXPOSE 8080

# Environment variables
ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+UnlockExperimentalVMOptions -Djava.net.preferIPv4Stack=true" \
    TZ=UTC \
    LANG=en_US.UTF-8 \
    PAYARA_MICRO_HOME=/opt/payara

# Run Payara Micro with the deployed WAR
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar /opt/payara/payara-micro.jar \
    --deploy /opt/payara/deployments/cargo-tracker.war \
    --contextroot / \
    --port 8080 \
    --noCluster"]
