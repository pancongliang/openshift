
### Example Spring Boot Application(multi-line log)

* Install jdk and maven
  ```
  yum install -y java-17-openjdk-devel

  wget https://archive.apache.org/dist/maven/maven-3/3.8.1/binaries/apache-maven-3.8.1-bin.tar.gz
  tar -zxvf apache-maven-3.8.1-bin.tar.gz && mv apache-maven-3.8.1 /usr/local/
  echo 'export MAVEN_HOME=/usr/local/apache-maven-3.8.1/' >> /etc/profile
  echo 'export PATH=${PATH}:${MAVEN_HOME}/bin' >> /etc/profile
  source /etc/profile
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
