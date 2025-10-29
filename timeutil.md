# timeutil

A timing utility module for ComputerCraft that provides persistent interval management with two different timing modes: absolute time-based and accumulated runtime-based. Features: Absolute time intervals (based on system time), accumulated time intervals (based on actual runtime), persistent state across computer restarts, pretty-printed time formatting, manual execution control, and automatic interval management with run loop.

## Functions

### `module.every(cb, intervalTime, fileName)`

Create an absolute time-based interval that runs based on system time This type of interval will "catch up" if the computer was offline, running immediately if the interval time has passed since the last recorded execution.

**Parameters:**

- `cb` (function): Callback function to execute when interval triggers
- `intervalTime` (number): Interval duration in seconds
- `fileName` (string): File path to persist the last run timestamp

**Returns:** TimeutilInterval # Interval object with control methods

### `module.everyLoaded(cb, intervalTime, fileName)`

Create a runtime-based interval that accumulates time only when the program is running This type of interval will NOT catch up after downtime, only counting actual runtime. Useful for operations that should happen after X seconds of actual program execution.

**Parameters:**

- `cb` (function): Callback function to execute when interval triggers
- `intervalTime` (number): Interval duration in seconds of actual runtime
- `fileName` (string): File path to persist the accumulated elapsed time

**Returns:** TimeutilInterval # Interval object with control methods

### `module.run()`

Start the main interval management loop This function blocks and continuously checks all registered intervals, executing them when their time has elapsed. Runs indefinitely until terminated.

### `module.getRelativeTime(sec)`

Format a duration in seconds into a human-readable relative time string

**Parameters:**

- `sec` (number): Duration in seconds

**Returns:** string # Formatted time string (e.g., "5.2 minutes", "1 day", "30 seconds")

