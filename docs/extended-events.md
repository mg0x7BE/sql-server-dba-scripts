# Extended Events reference

Reference: Extended Events terminology.

Extended Events (XEvents) is the lightweight tracing system in SQL Server. A session ties together what to capture, where to send it, and how to filter it.

## Glossary

- Events: Points of interest during code execution.
- Targets: Destinations the captured data is sent to (for example, files or ring buffer).
- Actions: Extra data collected when an event fires (for example, capturing the execution plan).
- Predicates: Dynamic filters applied to event capture.
- Types: Definitions of the objects Extended Events works with.
- Maps: Lookups that map values to strings (for example, codes to descriptions).

## system_health

`system_health` is the always-on default session. It starts with the instance and captures errors, deadlocks, long latch and lock waits, and other health signals. Use it as a first stop before creating a custom session.

## Runnable examples

See `diagnostics/extended-events.sql` for runnable session, target, and query examples.
