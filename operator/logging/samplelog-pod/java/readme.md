
### Example Spring Boot Application(multi-line log)

* Install jdk and maven
  ```
  yum install -y java-17-openjdk-devel
  yum install -y maven
  ```

* Build Spring Boot
  ```
  git clone https://github.com/pancongliang/multi-line-log.git
  mvn clean package
  ```

* Build Spring Boot
  ```
  git clone https://github.com/pancongliang/multi-line-log.git
  cd multi-line-log
  mvn clean package
  ```

* Build image
  ```
  podman build -t docker.registry.example.com:5000/multiline-java/multiline-java:latest .
  podman push docker.registry.example.com:5000/multiline-java/multiline-java:latest
  ```

* Create app pod
  ```
  oc new-project spring-boot-app
  oc new-app --name spring-boot-app --docker-image docker.registry.example.com:5000/multiline-java/multiline-java:latest

  oc logs spring-boot-app-dcb9c57b5-r8vw2
  ```
