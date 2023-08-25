# Install required packages
yum install -y wget net-tools podman bind-utils bind haproxy git bash-completion vim jq nfs-utils httpd httpd-tools skopeo httpd-manual

# openshift-install:
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/$OCP_RELEASE/openshift-install-linux.tar.gz
tar xvf openshift-install-linux.tar.gz
mv openshift-install /usr/local/bin/

# oc CLI tools:
curl https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/openshift-client-linux.tar.gz --output openshift-client-linux.tar.gz
tar xvf openshift-client-linux.tar.gz
mv oc kubectl /usr/local/bin/

# oc-mirror tools:
curl -O https://mirror.openshift.com/pub/openshift-v4/x86_64/clients/ocp/stable/oc-mirror.tar.gz
tar -xvf oc-mirror.tar.gz
chmod a+x oc-mirror && mv oc-mirror /usr/local/bin/

# butane tools:
curl https://mirror.openshift.com/pub/openshift-v4/clients/butane/latest/butane --output butane
chmod a+x butane && mv butane /usr/local/bin/

ls -ltr /usr/local/bin/

# Disable firewalld
systemctl disable firewalld
systemctl stop firewalld
systemctl status firewalld |grep Active -B1

# Disable SELinux
sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
cat /etc/selinux/config |grep 'SELINUX=disabled'

# Reboot the system
reboot
