/**
 * Telemetry + structured logging.
 *
 * Application Insights auto-instrumentation is enabled only when a connection
 * string is present, so local runs stay quiet. Logs are emitted as single-line
 * JSON for easy correlation in Log Analytics. Secrets must never be logged.
 */
import appInsights from "applicationinsights";

let telemetryStarted = false;

export function initTelemetry(connectionString?: string): void {
  if (!connectionString || telemetryStarted) return;
  appInsights
    .setup(connectionString)
    .setAutoCollectConsole(true, true)
    .setAutoCollectExceptions(true)
    .setAutoCollectRequests(true)
    .setSendLiveMetrics(false)
    .start();
  telemetryStarted = true;
}

export type LogLevel = "info" | "warn" | "error";

export function log(level: LogLevel, message: string, meta: Record<string, unknown> = {}): void {
  const entry = { ts: new Date().toISOString(), level, message, ...meta };
  const line = JSON.stringify(entry);
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}
