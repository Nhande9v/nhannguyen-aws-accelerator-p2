// app.js

const express = require('express');
const app = express();
const PORT = 8080;

// Middleware log đơn giản ra console
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

// 1. API Thành công (Dùng để test tỉ lệ Availability thành công)
app.get('/api/success', (req, res) => {
  res.status(200).json({ status: "Success", message: "Chào mừng bạn đến với AzuraHaven!" });
});

// 2. API Bị Lỗi 500 (Dùng để giả lập sập hệ thống, test Fast Burn Rate Alert)
app.get('/api/error', (req, res) => {
  res.status(500).json({ status: "Error", message: "Hệ thống gặp sự cố nghiêm trọng!" });
});

// 3. API Chạy Chậm (Dùng để test Latency SLI)
app.get('/api/slow', async (req, res) => {
  // Ngẫu nhiên bắt ứng dụng ngủ (sleep) 600ms hoặc chạy nhanh 30ms
  const delay = Math.random() > 0.5 ? 600 : 30;
  await new Promise(resolve => setTimeout(resolve, delay));
  res.status(200).json({ status: "Success", duration: `${delay}ms` });
});

app.listen(PORT, () => {
  console.log(`🚀 App giả lập đang chạy tại http://localhost:${PORT}`);
});