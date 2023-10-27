### Automatically approve csr

* Create project
  ```
  oc adm new-project cronjob-csr
  ```

* Provide the `default` service account with the role of `cluster-admin`
  ```
  oc adm policy add-cluster-role-to-user cluster-admin -z default -n openshift-cron-jobs
  ```

* Create cronjob
  ```
  oc create -f Cronjob .yaml
  ```
