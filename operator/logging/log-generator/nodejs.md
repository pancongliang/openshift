### Build samplelog-app image
```bash
cat > app.js << EOF
const http = require('http');

const server = http.createServer((req, res) => {
    const timestamp = new Date().toISOString();
    console.log(`${timestamp} INFO: This is 
a multiline nodejs app


log.`);
    res.end('Hello World\n');
});

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
EOF

cat > package.json << EOF
{
    "name": "nodejs-logger",
    "version": "1.0.0",
    "main": "app.js",
    "scripts": {
        "start": "node app.js"
    },
    "dependencies": {}
}
EOF

cat > Dockerfile << EOF
FROM registry.redhat.io/ubi8/nodejs-14:latest
WORKDIR /app
COPY package.json ./
RUN npm install
COPY app.js ./
EXPOSE 3000
CMD ["node", "app.js"]
EOF

podman build -t docker.registry.example.com:5000/nodejs/nodejs-app:latest .
podman push docker.registry.example.com:5000/nodejs/nodejs-app:latest
```

### Create samplelog app serive
```bash
oc new-project nodejs-log
oc new-app --name nodejs-log --docker-image docker.registry.example.com:5000/nodejs/nodejs-app:latest
oc expose svc nodejs-log --hostname nodejs.apps.ocp4.example.com

curl http://nodejs.apps.ocp4.example.com
Hello World

oc -n nodejs-log logs nodejs-log-5f4cdb9bcf-rvzk8
2023-12-26T18:23:47.729Z INFO: This is 
a multiline nodejs app


log.
```


