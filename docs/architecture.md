# Architecture Overview

## High-level components

- **macos-app** (SwiftUI): Presents the UI, orchestrates automation, and talks to Safari via the Accessibility APIs (AXUIElement / CGEvent).
- **ScrollAutomationEngine**: Consumes `AutomationInstruction` values and performs the requested scroll/press actions while emitting status updates.
- **LoadMoreStrategyClient**: Planned bridge to the Java strategy process. Currently ships with a stubbed implementation (fallback scroll + text-match heuristics) so that the UI can be exercised without the external process.
- **java-strategy**: Console program that receives `LoadMoreRequest` JSON and responds with `LoadMoreResponse` actions. Strategies are registered per-site or per-host, letting you add new logic in isolation.

## Data contract (Swift ↔ Java)

| Field | Direction | Description |
| --- | --- | --- |
| `siteId` | Swift → Java | Identifier from `SiteProfile.identifier`. |
| `url` | Swift → Java | Current tab URL (planned). |
| `visibleButtons[]` | Swift → Java | Snapshot of AX-discovered buttons (`title`, `role`). |
| `action` | Java → Swift | `PRESS`, `SCROLL`, `WAIT`, `NO_ACTION`, `ERROR`. |
| `query` | Java → Swift | Accessibility selector (title substring, optional role). |
| `scrollDistance` | Java → Swift | Pixel distance for wheel scroll events (negative = scroll down). |
| `waitSeconds` | Java → Swift | Delay before requesting the next instruction. |
| `message` | Java → Swift | Human-readable note, surfaced in the UI log. |

The JSON schema matches the concrete Java classes `LoadMoreRequest` / `LoadMoreResponse` and the Swift types `AutomationInstruction` / `AccessibilitySelector`.

## Expected control loop

1. Swift app asks `LoadMoreStrategyClient` for the next instruction (site-aware).
2. The client forwards the current page context to `StrategyServer` via STDIN.
3. Java strategy resolves a `LoadMoreResponse` and returns JSON on STDOUT.
4. Swift converts the response into `AutomationInstruction` and calls `ScrollAutomationEngine`.
5. Engine triggers scroll or button press via `SafariAccessibilityController` and emits status back to the UI.
6. Loop continues until the user stops automation or an error occurs.

## Extending strategies

To add a site-specific strategy in Java:

1. Implement `LoadMoreStrategy#evaluate` (e.g., DOM parse, heuristic, machine learning).
2. Register the implementation in `StrategyRegistry.defaultRegistry()` or load dynamically from configuration.
3. Update Swift `sites.json` so the UI exposes the new site profile.

Swift-side adjustments typically include mapping new response fields to `AutomationInstruction` and adding configuration keys if the Java side requires them.
