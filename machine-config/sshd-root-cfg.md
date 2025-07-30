
#### 1. To allow the root user to log in via SSH, set PasswordAuthentication and PermitRootLogin to yes in the 40-rhcos-defaults.conf file
~~~
$ cat  /etc/ssh/sshd_config.d/40-rhcos-defaults.conf
# Disable PasswordAuthentication and PermitRootLogin to preserve RHCOS 8
# defaults for now
# See: https://issues.redhat.com/browse/OCPBUGS-11613
# See: https://github.com/openshift/os/issues/1216
PasswordAuthentication yes
PermitRootLogin yes

# Enable ClientAliveInterval and set to 180
# See: https://bugzilla.redhat.com/show_bug.cgi?id=1701050
ClientAliveInterval 180
~~~

####2. Base64-encode the modified 40-rhcos-defaults.conf file, then create a MachineConfig
~~~
BASE64=$(base64 -w 0 /etc/ssh/sshd_config.d/40-rhcos-defaults.conf)
cat << EOF > ./99-worker-sshd-configuration.yaml
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: worker
  name: 99-worker-sshd-configuration
spec:
  config:
    ignition:
      config: {}
      security:
        tls: {}
      timeouts: {}
      version: 3.4.0
    networkd: {}
    passwd: {}
    storage:
      files:
      - contents:
          source: data:text/plain;charset=utf-8;base64,${BASE64}
        mode: 420
        overwrite: true
        path: /etc/ssh/sshd_config.d/40-rhcos-defaults.conf
  osImageURL: ""
EOF
~~~
