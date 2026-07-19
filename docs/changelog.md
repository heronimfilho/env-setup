# Changelog

All notable changes are documented here. The project follows Semantic Versioning.

## 0.4.0 - Unreleased

### Added

- live heartbeat and configurable timeout for native commands;
- execution summaries, restart guidance, stable error codes, and log locations;
- `-Doctor`, `-Status`, `-ListTasks`, `-ExportConfig`, `-ResetSelections`, `-ShowLastLog`, and `-CollectDiagnostics`;
- text, no-color, and JSON-lines output modes;
- interactive plan preview, task counts, profile shortcuts, defaults restoration, and search;
- immutable self-update through `release-manifest.json`;
- semantic version file and tag-based release workflow;
- public contribution, security, recovery, architecture, and task-authoring documentation;
- pinned GitHub Actions, PSScriptAnalyzer, ShellCheck, Markdownlint, Actionlint, and secret-format scanning.

### Changed

- bootstrap can safely update an existing non-Git installation with rollback;
- task state records the active phase, result, stable error code, and last message;
- repository documentation now separates quick-start material from detailed guides.

## 0.3.0 - 2026-07-19

- added visible task phases and elapsed timing;
- persisted interactive selections and setup options;
- fixed generated task command scope on clean installations.

## 0.2.0 - 2026-07-18

- introduced resumable task execution, profiles, interactive selection, immutable bootstrap, WSL configuration, Git/GitHub integration, VS Code profiles, and automated tests.
