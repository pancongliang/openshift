FROM registry.access.redhat.com/ubi8/openjdk-17:latest

WORKDIR /app

COPY target/*.jar app.jar

ENTRYPOINT ["java","-jar","/app/app.jar"]
