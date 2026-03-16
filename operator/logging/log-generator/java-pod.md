
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

* Change fluent.conf to recognize multi-line log entries
  ```
  oc -n openshift-logging edit cm collector
  # from
      # Concat log lines of container logs, and send to INGRESS pipeline
      <label @CONCAT>
        <filter kubernetes.**>
          @type concat
          key message
          partial_key logtag
          partial_value P
          separator ''
        </filter>
  
        <match kubernetes.**>
          @type relabel
          @label @INGRESS
        </match>
      </label>
  
  # Change to
      # Concat log lines of container logs, and send to INGRESS pipeline
      <label @CONCAT>
        <filter kubernetes.**>
          @type concat
          key message
          multiline_start_regexp /^[\d]{4}-[\d]{2}-[\d]{2}T[\d]{2}:[\d]{2}:[\d]{2}\.[\d]{3}Z/
          flush_interval 1
          timeout_label @INGRESS
        </filter>
  
        <match kubernetes.**>
          @type relabel
          @label @INGRESS
        </match>
      </label>

  # Reboot collector pod
  oc delete po collector-2lwnh collector-9r6nw collector-9wzdv collector-c4q9k collector-hznsm collector-pr2jx collector-twglq  -n openshift-logging
  ```
* Kibana log
  ```
  December 26th 2023, 16:06:00.170	2023-12-26T08:06:00.169Z ERROR 1 --- [     scheduling-1] o.s.s.s.TaskUtils$LoggingErrorHandler    : Unexpected error occurred   in scheduled task
  
  java.lang.RuntimeException: Error happened
  	at com.example.demo.FluentdMultilineJavaApplication.logException  (FluentdMultilineJavaApplication.java:38) ~[!/:na]
  	at jdk.internal.reflect.GeneratedMethodAccessor2.invoke(Unknown Source) ~[na:na]
  	at java.base/jdk.internal.reflect.DelegatingMethodAccessorImpl.invoke  (DelegatingMethodAccessorImpl.java:43) ~[na:na]
  	at java.base/java.lang.reflect.Method.invoke(Method.java:568) ~[na:na]
  	at org.springframework.scheduling.support.ScheduledMethodRunnable.runInternal  (ScheduledMethodRunnable.java:130) ~[spring-context-6.1.2.jar!/:6.1.2]
  	at org.springframework.scheduling.support.ScheduledMethodRunnable.lambda$run$2  (ScheduledMethodRunnable.java:124) ~[spring-context-6.1.2.jar!/:6.1.2]
  	at io.micrometer.observation.Observation.observe(Observation.java:499) ~  [micrometer-observation-1.12.1.jar!/:1.12.1]
  	at org.springframework.scheduling.support.ScheduledMethodRunnable.run  (ScheduledMethodRunnable.java:124) ~[spring-context-6.1.2.jar!/:6.1.2]
  	at org.springframework.scheduling.support.DelegatingErrorHandlingRunnable.run  (DelegatingErrorHandlingRunnable.java:54) ~[spring-context-6.1.2.jar!/:6.1.2]
  	at java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.  java:539) ~[na:na]
  	at java.base/java.util.concurrent.FutureTask.runAndReset(FutureTask.java:305) ~  [na:na]
  	at java.base/java.util.concurrent.ScheduledThreadPoolExecutor$ScheduledFutureTask.  run(ScheduledThreadPoolExecutor.java:305) ~[na:na]
  	at java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.  java:1136) ~[na:na]
  	at java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.  java:635) ~[na:na]
  	at java.base/java.lang.Thread.run(Thread.java:840) ~[na:na]
  Caused by: org.springframework.beans.factory.NoSuchBeanDefinitionException: No bean   named 'test' available
  	at org.springframework.beans.factory.support.DefaultListableBeanFactory.  getBeanDefinition(DefaultListableBeanFactory.java:895) ~[spring-beans-6.1.2.jar!/  :6.1.2]
  	at org.springframework.beans.factory.support.AbstractBeanFactory.  getMergedLocalBeanDefinition(AbstractBeanFactory.java:1319) ~[spring-beans-6.1.2.  jar!/:6.1.2]
  	at org.springframework.beans.factory.support.AbstractBeanFactory.doGetBean  (AbstractBeanFactory.java:299) ~[spring-beans-6.1.2.jar!/:6.1.2]
  	at org.springframework.beans.factory.support.AbstractBeanFactory.getBean  (AbstractBeanFactory.java:199) ~[spring-beans-6.1.2.jar!/:6.1.2]
  	at org.springframework.context.support.AbstractApplicationContext.getBean  (AbstractApplicationContext.java:1232) ~[spring-context-6.1.2.jar!/:6.1.2]
  	at com.example.demo.FluentdMultilineJavaApplication.logException  (FluentdMultilineJavaApplication.java:36) ~[!/:na]
  	... 14 common frames omitted
  
  December 26th 2023, 16:05:58.588	2023-12-26T08:05:58.588Z  INFO 1 --- [     scheduling-1] c.e.d.FluentdMultilineJavaApplication    : This is 
  a multiline
  
  
  log
  ```
