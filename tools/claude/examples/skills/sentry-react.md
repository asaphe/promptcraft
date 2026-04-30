---
name: sentry-react
description: Load Sentry instrumentation patterns for a React webapp — error tracking, tracing spans, and structured logging. Use when adding or modifying Sentry integration. Usage - /sentry-react
user-invocable: true
allowed-tools: Read, Grep, Glob
---

# Sentry Instrumentation Guide (React)

Reference patterns for instrumenting Sentry in a React webapp.

## Error / Exception Tracking

Use `Sentry.captureException(error)` to capture an exception and log it in Sentry. Use this in `try` / `catch` blocks or areas where exceptions are expected.

```javascript
try {
  await riskyOperation();
} catch (err) {
  Sentry.captureException(err);
  throw err;  // re-raise unless the caller can handle it
}
```

## Tracing

Spans should be created for meaningful actions: button clicks, API calls, expensive computations. Use `Sentry.startSpan` to create spans with descriptive names and operation tags. Child spans can exist within a parent span.

### Custom Span — Component Actions

```javascript
function TestComponent() {
  const handleTestButtonClick = () => {
    Sentry.startSpan(
      {
        op: 'ui.click',
        name: 'Test Button Click',
      },
      (span) => {
        span.setAttribute('config', 'some config');
        span.setAttribute('metric', 'some metric');
        doSomething();
      },
    );
  };
  return (
    <button type="button" onClick={handleTestButtonClick}>
      Test Sentry
    </button>
  );
}
```

### Custom Span — API Calls

```javascript
async function fetchUserData(userId) {
  return Sentry.startSpan(
    {
      op: 'http.client',
      name: `GET /api/users/${userId}`,
    },
    async () => {
      const response = await fetch(`/api/users/${userId}`);
      const data = await response.json();
      return data;
    },
  );
}
```

## Logging

Import Sentry: `import * as Sentry from "@sentry/react"`. Reference the logger: `const { logger } = Sentry`.

### Configuration

#### Baseline

```javascript
import * as Sentry from '@sentry/react';
Sentry.init({
  dsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
  enableLogs: true,
});
```

#### Console Logging Integration

```javascript
Sentry.init({
  dsn: 'https://examplePublicKey@o0.ingest.sentry.io/0',
  integrations: [
    Sentry.consoleLoggingIntegration({ levels: ['log', 'error', 'warn'] }),
  ],
});
```

### Logger Examples

Use `logger.fmt` as a template literal to bring variables into structured logs.

```javascript
logger.trace('Starting database connection', { database: 'users' });
logger.debug(logger.fmt`Cache miss for user: ${userId}`);
logger.info('Updated profile', { profileId: 345 });
logger.warn('Rate limit reached for endpoint', {
  endpoint: '/api/results/',
  isEnterprise: false,
});
logger.error('Failed to process payment', {
  orderId: 'order_123',
  amount: 99.99,
});
logger.fatal('Database connection pool exhausted', {
  database: 'users',
  activeConnections: 100,
});
```

## Before Instrumenting

1. Check the existing Sentry setup in the webapp's entry point to understand the current `Sentry.init` configuration.
2. Search the codebase for existing Sentry usage patterns: `grep -rn 'Sentry\.' src/` to stay consistent.
3. Consult the [Sentry React SDK docs](https://docs.sentry.io/platforms/javascript/guides/react/) if you need features beyond what's documented here.
