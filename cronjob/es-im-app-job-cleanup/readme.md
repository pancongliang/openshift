### Automatically clean up openshift-logging's es-im-app-job

* Create `es-im-app-job-cleanup` cronjob 
  ```
  oc new-project es-im-app-job-cleanup
  oc create serviceaccount es-im-app-job-cleanup-sa
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/cronjob/es-im-app-job-cleanup/01-cluster-role-binding.yaml
  oc create -f https://raw.githubusercontent.com/pancongliang/openshift/main/cronjob/es-im-app-job-cleanup/02-es-im-app-job-cleanup.yaml
  ```

* The latest job status is "Complete" and the old job status is "Error". At this point, run the "es-im-app-job-cleanup" cronjob. The expected effect is that old jobs are automatically deleted
  ```
  oc get po -n openshift-logging |grep elasticsearch-im-app
  elasticsearch-im-app-28242234-vhw7x             0/1     Error       0               4m14s
  elasticsearch-im-app-28242237-pjvs5             0/1     Completed   0               74s

  oc get job -n openshift-logging |grep elasticsearch-im-app
  elasticsearch-im-app-28242234     0/1           4m1s       4m1s
  elasticsearch-im-app-28242237     1/1           13s        61s

  oc create job es-im-app-job-cleanup  --from=cronjob/es-im-app-job-cleanup -n es-im-app-job-cleanup

  oc get job -n openshift-logging |grep elasticsearch-im-app
  elasticsearch-im-app-28242237     1/1           13s        114s

  oc get po -n openshift-logging |grep elasticsearch-im-app
  elasticsearch-im-app-28242237-pjvs5             0/1     Completed   0               118s
  ```

* The latest job status is "Error" and the old job status is "Complete". At this point, run the "es-im-app-job-cleanup" cronjob. The expected effect is that new/old jobs are not deleted
  ```
  oc get po -n openshift-logging |grep elasticsearch-im-app
  elasticsearch-im-app-28242237-pjvs5             0/1     Completed   0               5m32s
  elasticsearch-im-app-28242240-b9t5c             0/1     Error       0               2m32s

  oc get job -n openshift-logging |grep elasticsearch-im-app
  elasticsearch-im-app-28242237     1/1           13s        5m41s
  elasticsearch-im-app-28242240     0/1           2m41s      2m41s

  oc create job es-im-app-job-cleanup-1  --from=cronjob/es-im-app-job-cleanup -n es-im-app-job-cleanup

  oc get po -n openshift-logging |grep elasticsearch-im-app
  elasticsearch-im-app-28242237-pjvs5             0/1     Completed   0               6m30s
  elasticsearch-im-app-28242243-6mqh7             0/1     Error       0               30s

  oc get job -n openshift-logging |grep elasticsearch-im-app
  elasticsearch-im-app-28242237     1/1           13s        6m32s
  elasticsearch-im-app-28242243     0/1           32s        32s
  ```
