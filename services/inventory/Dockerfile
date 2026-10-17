ARG OTEL_JAVAAGENT_VERSION=2.31.1

FROM eclipse-temurin:21-jdk-alpine AS build
WORKDIR /src
COPY src/ ./src/
RUN mkdir -p /out && javac -d /out src/*.java

# The agent jar is baked into the image, but it is INERT until the deployment
# sets JAVA_TOOL_OPTIONS (see k8s/apps/instrumented).
FROM eclipse-temurin:21-jre-alpine AS agent
ARG OTEL_JAVAAGENT_VERSION
RUN apk add --no-cache curl && mkdir -p /otel && \
    curl -fsSL -o /otel/opentelemetry-javaagent.jar \
      "https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_JAVAAGENT_VERSION}/opentelemetry-javaagent.jar"

FROM eclipse-temurin:21-jre-alpine
WORKDIR /app
COPY --from=build /out /app
COPY --from=agent /otel/opentelemetry-javaagent.jar /otel/opentelemetry-javaagent.jar
EXPOSE 8081
CMD ["java", "-cp", "/app", "Inventory"]
