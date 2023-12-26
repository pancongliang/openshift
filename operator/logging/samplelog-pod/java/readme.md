
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

  oc -n spring-boot-app logs spring-boot-app-6644797d54-7tfwh
    2023-12-26T05:53:53.588Z  INFO 1 --- [   scheduling-1] c.e.d.FluentdMultilineJavaApplication    : This is 
  a multiline
  
  
  log
  2023-12-26T05:53:58.588Z ERROR 1 --- [   scheduling-1] o.s.s.s.TaskUtils$LoggingErrorHandler    : Unexpected error occurred in scheduled task
  
  java.lang.RuntimeException: Error happened
          at com.example.demo.FluentdMultilineJavaApplication.logException(FluentdMultilineJavaApplication.java:38) ~[!/:na]
          at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke0(Native Method) ~[na:na]
          at java.base/jdk.internal.reflect.NativeMethodAccessorImpl.invoke(NativeMethodAccessorImpl.java:77) ~[na:na]
          at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke(DelegatingMethodAccessorImpl.java:43) ~[na:na]
          at java.base/java.lang.reflect.Method.invoke(Method.java:568) ~[na:na]
          at org.springframework.scheduling.support.ScheduledMethodRunnable.runInternal(ScheduledMethodRunnable.java:130) ~[spring-context-6.1.2.jar!/  :6.1.2]
          at org.springframework.scheduling.support.ScheduledMethodRunnable.lambda$run$2(ScheduledMethodRunnable.java:124) ~[spring-context-6.1.2.jar!/  :6.1.2]
          at io.micrometer.observation.Observation.observe(Observation.java:499) ~[micrometer-observation-1.12.1.jar!/:1.12.1]
          at org.springframework.scheduling.support.ScheduledMethodRunnable.run(ScheduledMethodRunnable.java:124) ~[spring-context-6.1.2.jar!/:6.1.2]
          at org.springframework.scheduling.support.DelegatingErrorHandlingRunnable.run(DelegatingErrorHandlingRunnable.java:54) ~[spring-context-6.1.  2.jar!/:6.1.2]
          at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:539) ~[na:na]
          at java.base/java.util.concurrent.FutureTask.runAndReset(FutureTask.java:305) ~[na:na]
          at java.base/java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.run(ScheduledThreadPoolExecutor.java:305) ~[na:na]
          at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1136) ~[na:na]
          at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:635) ~[na:na]
          at java.base/java.lang.Thread.run(Thread.java:840) ~[na:na]
  Caused by: org.springframework.beans.factory.NoSuchBeanDefinitionException: No bean named 'test' available
          at org.springframework.beans.factory.support.DefaultListableBeanFactory.getBeanDefinition(DefaultListableBeanFactory.java:895) ~  [spring-beans-6.1.2.jar!/:6.1.2]
          at org.springframework.beans.factory.support.AbstractBeanFactory.getMergedLocalBeanDefinition(AbstractBeanFactory.java:1319) ~  [spring-beans-6.1.2.jar!/:6.1.2]
          at org.springframework.beans.factory.support.AbstractBeanFactory.doGetBean(AbstractBeanFactory.java:299) ~[spring-beans-6.1.2.jar!/:6.1.2]
          at org.springframework.beans.factory.support.AbstractBeanFactory.getBean(AbstractBeanFactory.java:199) ~[spring-beans-6.1.2.jar!/:6.1.2]
          at org.springframework.context.support.AbstractApplicationContext.getBean(AbstractApplicationContext.java:1232) ~[spring-context-6.1.2.jar!/  :6.1.2]
          at com.example.demo.FluentdMultilineJavaApplication.logException(FluentdMultilineJavaApplication.java:36) ~[!/:na]
          ... 15 common frames omitted
  ```
