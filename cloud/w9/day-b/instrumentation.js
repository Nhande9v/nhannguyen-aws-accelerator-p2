// instrumentation.js
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { getNodeAutoInstrumentations } = require('@opentelemetry/auto-instrumentations-node');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-metrics-otlp-http');// Chuyển sang http
const { OTLPLogExporter } = require('@opentelemetry/exporter-logs-otlp-http'); // Chuyển sang http
const { PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { SimpleLogRecordProcessor } = require('@opentelemetry/sdk-logs');

// Cấu hình gửi Metric về OTel Collector qua cổng HTTP 4318
const metricExporter = new OTLPMetricExporter({
  url: 'http://127.0.0.1:4318/v1/metrics',// Endpoint chuẩn HTTP của OTel
});

// Cấu hình gửi Log về OTel Collector qua cổng HTTP 4318
const logExporter = new OTLPLogExporter({
  url: 'http://127.0.0.1:4318/v1/logs', // Endpoint chuẩn HTTP của OTel
});

const sdk = new NodeSDK({
  serviceName: 'mock-booking-service',
  metricReader: new PeriodicExportingMetricReader({
    exporter: metricExporter,
    exportIntervalMillis: 2000, // 2 giây đẩy một lần
  }),
  logRecordProcessor: new SimpleLogRecordProcessor(logExporter),
  instrumentations: [
    getNodeAutoInstrumentations({
      '@opentelemetry/instrumentation-http': {
        clearTimingHooks: true,
      },
    }),
  ],
});

sdk.start();
console.log("🔥 OpenTelemetry SDK bản HTTP đã được kích hoạt ngầm...");

process.on('SIGTERM', () => {
  sdk.shutdown()
    .then(() => console.log('SDK đã tắt'))
    .catch((error) => console.log('Lỗi tắt SDK', error))
    .finally(() => process.exit(0));
});