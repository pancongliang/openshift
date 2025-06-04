## Agent-based Installer

### Defining environment variables
~~~
wget https://raw.githubusercontent.com/pancongliang/openshift/refs/heads/main/installing/agent-based/pre-inst.sh
vim pre-inst.sh
~~~

### Installing the Infrastructure and Creating the agent-config and install-config Files
~~~
sudo dnf install -y bind-utils bind haproxy
sudo dnf install /usr/bin/nmstatectl -y

bash pre-inst.sh
~~~

### Creating and booting the agent image

- If it is a vmware environment, enable [disk.EnableUUID](https://access.redhat.com/solutions/4606201) for all nodes)
~~~
openshift-install --dir ocp-inst agent create image
~~~

### Tracking and verifying installation progress 
~~~
openshift-install --dir ocp-inst agent wait-for bootstrap-complete --log-level=info
openshift-install --dir ocp-inst agent wait-for install-complete
~~~
