## How to use the Compliance Operator in Red Hat OpenShift Container Platform 4

### Install Compliance Operator

* Install the Operator using the default namespace
  ```
  export CHANNEL_NAME="stable"
  export CATALOG_SOURCE_NAME="redhat-operators"
  curl -s https://raw.githubusercontent.com/pancongliang/openshift/main/operator/compliance/01-operator.yaml | envsubst | oc apply -f -

  sleep 6
  
  oc patch installplan $(oc get ip -n openshift-compliance -o=jsonpath='{.items[?(@.spec.approved==false)].metadata.name}') -n openshift-compliance --type merge --patch '{"spec":{"approved":true}}'

  oc get ip -n openshift-compliance
  ```

### Listing available compliance profiles
* View the profilebundle object
  ```
  $ oc get profilebundle.compliance -n openshift-compliance
  NAME     CONTENTIMAGE                                                                                                                               CONTENTFILE         STATUS
  ocp4     registry.redhat.io/compliance/openshift-compliance-content-rhel8@sha256:2ea5a1a3be322beb76f639ac486d36a28f5af4e7a3d83d08b69c6a65d4ec8079   ssg-ocp4-ds.xml     VALID
  rhcos4   registry.redhat.io/compliance/openshift-compliance-content-rhel8@sha256:2ea5a1a3be322beb76f639ac486d36a28f5af4e7a3d83d08b69c6a65d4ec8079   ssg-rhcos4-ds.xml 
    ```

* View the compliance profiles
  ```
  $ oc get profile.compliance -n openshift-compliance
  NAME                 AGE
  ocp4-cis             2m23s
  ocp4-cis-node        2m23s
  ocp4-e8              2m23s
  ocp4-high            2m22s
  ocp4-high-node       2m22s
  ocp4-moderate        2m22s
  ocp4-moderate-node   2m22s
  ocp4-nerc-cip        2m22s
  ocp4-nerc-cip-node   2m22s
  ocp4-pci-dss         2m22s
  ocp4-pci-dss-node    2m22s
  rhcos4-e8            2m17s
  rhcos4-high          2m17s
  rhcos4-moderate      2m17s
  rhcos4-nerc-cip      2m17s
  ```

* Only view the Profile related to "rhcos4" through label.
  ```
  $ oc get profile.compliance -l compliance.openshift.io/profile-bundle=rhcos4 -n openshift-compliance
  NAME              AGE
  rhcos4-e8         2m39s
  rhcos4-high       2m39s
  rhcos4-moderate   2m39s
  rhcos4-nerc-cip   2m39s
  ```

* View the rules contained in the Profile named "rhcos4-e8".
  ```
  $ oc get profile.compliance rhcos4-e8 -n openshift-compliance -o json | jq .rules
  [
    "rhcos4-accounts-no-uid-except-zero",
    "rhcos4-audit-rules-dac-modification-chmod",
    "rhcos4-audit-rules-dac-modification-chown",
    "rhcos4-audit-rules-execution-chcon",
    "rhcos4-audit-rules-execution-restorecon",
    "rhcos4-audit-rules-execution-semanage",
    "rhcos4-audit-rules-execution-setfiles",
    "rhcos4-audit-rules-execution-setsebool",
    "rhcos4-audit-rules-execution-seunshare",
    "rhcos4-audit-rules-kernel-module-loading-delete",
    "rhcos4-audit-rules-kernel-module-loading-finit",
    "rhcos4-audit-rules-kernel-module-loading-init",
    "rhcos4-audit-rules-login-events",
    "rhcos4-audit-rules-login-events-faillock",
    "rhcos4-audit-rules-login-events-lastlog",
    "rhcos4-audit-rules-login-events-tallylog",
    "rhcos4-audit-rules-networkconfig-modification",
    "rhcos4-audit-rules-sysadmin-actions",
    "rhcos4-audit-rules-time-adjtimex",
    "rhcos4-audit-rules-time-clock-settime",
    "rhcos4-audit-rules-time-settimeofday",
    "rhcos4-audit-rules-time-stime",
    "rhcos4-audit-rules-time-watch-localtime",
    "rhcos4-audit-rules-usergroup-modification",
    "rhcos4-auditd-data-retention-flush",
    "rhcos4-auditd-freq",
    "rhcos4-auditd-local-events",
    "rhcos4-auditd-log-format",
    "rhcos4-auditd-name-format",
    "rhcos4-auditd-write-logs",
    "rhcos4-configure-crypto-policy",
    "rhcos4-configure-ssh-crypto-policy",
    "rhcos4-no-empty-passwords",
    "rhcos4-selinux-policytype",
    "rhcos4-selinux-state",
    "rhcos4-service-auditd-enabled",
    "rhcos4-sshd-disable-empty-passwords",
    "rhcos4-sshd-disable-gssapi-auth",
    "rhcos4-sshd-disable-rhosts",
    "rhcos4-sshd-disable-root-login",
    "rhcos4-sshd-disable-user-known-hosts",
    "rhcos4-sshd-do-not-permit-user-env",
    "rhcos4-sshd-enable-strictmodes",
    "rhcos4-sshd-print-last-log",
    "rhcos4-sshd-set-loglevel-info",
    "rhcos4-sysctl-kernel-dmesg-restrict",
    "rhcos4-sysctl-kernel-kptr-restrict",
    "rhcos4-sysctl-kernel-randomize-va-space",
    "rhcos4-sysctl-kernel-unprivileged-bpf-disabled",
    "rhcos4-sysctl-kernel-yama-ptrace-scope",
    "rhcos4-sysctl-net-core-bpf-jit-harden"
  ]
  ``` 
