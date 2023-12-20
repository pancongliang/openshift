podman login -u admin -p password mirror.registry.example.com:8443

cat /root/pull-secret | jq . > ${XDG_RUNTIME_DIR}/containers/auth.json
