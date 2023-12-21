const express = require('express');
const app = express();
const port = 3000;

// 从环境变量中获取 Pod 信息
const podName = process.env.POD_NAME || 'Unknown Pod';
const nodeName = process.env.NODE_NAME || 'Unknown Node';

app.get('/', (req, res) => {
  console.log(JSON.stringify({
    event: "requestReceived",
    url: req.url,
    method: req.method,
    timestamp: new Date(),
    podName: podName,
    nodeName: nodeName
  }, null, 2));

  res.send('Hello World!');
});

app.listen(port, () => {
  console.log(`Example app listening at http://localhost:${port}`);
});
