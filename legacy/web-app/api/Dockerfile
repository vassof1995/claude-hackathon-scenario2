# Multi-stage: build the fat jar, then run it on a slim JRE.
FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q -DskipTests dependency:go-offline
COPY src ./src
RUN mvn -q -DskipTests package

FROM eclipse-temurin:21-jre-alpine
RUN apk add --no-cache curl
RUN addgroup -S contoso && adduser -S -G contoso contoso
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 CMD curl -sf http://localhost:8080/actuator/health || exit 1
USER contoso
ENTRYPOINT ["java", "-jar", "app.jar"]
