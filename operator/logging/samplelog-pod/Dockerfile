FROM registry.redhat.io/jboss-webserver-5/jws57-openjdk11-openshift-rhel8:5.7.3-2.1687186259

RUN rm -rf /deployments/*
COPY ./index.jsp /deployments/ROOT
