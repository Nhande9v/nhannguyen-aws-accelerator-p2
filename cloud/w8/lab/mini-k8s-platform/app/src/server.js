const express = require('express');

const app = express();

const PORT = process.env.PORT || 3000;

const APP_NAME = process.env.APP_NAME || 'Rental API';

app.get('/', (req, res) => {
    res.json({
    app: APP_NAME,
    status: "running"
  });
});

app.get('health', (req, res) => {
    res.status(200).send('OK');
});

app.listen(PORT, () => {
  console.log(`${APP_NAME} is running on port ${PORT}`);
});