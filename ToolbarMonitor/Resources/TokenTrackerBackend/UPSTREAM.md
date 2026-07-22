# TokenTracker quota backend

This directory vendors the quota-collection library from
[`mm7894215/TokenTracker`](https://github.com/mm7894215/TokenTracker), version
0.83.6. The upstream project is licensed under the MIT License; its license is
included in `LICENSE`.

ToolbarMonitor invokes `quota-runner.js` as a one-shot local collector. It does
not connect to or require the TokenTrackerBar application or its local server.
