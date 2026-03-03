
#### Allow root SSH login (set PasswordAuthentication and PermitRootLogin to yes)
```bash
$ cat  /etc/ssh/sshd_config.d/40-rhcos-defaults.conf
PasswordAuthentication yes
PermitRootLogin yes
```

#### Base64-encode the modified 40-rhcos-defaults.conf file, then create a MachineConfig
```
BASE64=$(base64 -w 0 /etc/ssh/sshd_config.d/40-rhcos-defaults.conf)
cat << EOF | oc apply -f -
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
```
