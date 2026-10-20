ARG OTEL_JAVAAGENT_VERSION=2.31.1
ARG LOG4J_VERSION=2.25.5

FROM eclipse-temurin:21-jdk-alpine AS build
ARG LOG4J_VERSION
WORKDIR /src
# Log4j 2 (api + core) straight from Maven Central: no build tool, just javac.
RUN apk add --no-cache curl && mkdir -p /out/lib && \
    for a in log4j-api log4j-core; do \
      curl -fsSL -o /out/lib/$a.jar \
        "https://repo1.maven.org/maven2/org/apache/logging/log4j/$a/${LOG4J_VERSION}/$a-${LOG4J_VERSION}.jar"; \
    done
COPY src/ ./src/
RUN javac -cp "/out/lib/*" -d /out src/*.java && cp src/log4j2.xml /out/

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
CMD ["java", "-cp", "/app:/app/lib/*", "Inventory"]
