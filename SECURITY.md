# Security Policy

## Supported versions

Security fixes are applied to the latest release and the `main` branch.

## Reporting a vulnerability

Do not open a public issue for a vulnerability that could expose credentials, private keys, arbitrary code execution, or an unsafe update path.

Use GitHub's private vulnerability reporting feature for this repository. Include:

- affected version or commit;
- reproduction steps;
- expected and actual behavior;
- impact assessment;
- suggested mitigation, when available.

You should receive an acknowledgement within seven days. A remediation timeline depends on severity and reproducibility.

## Security model

`env-setup` makes system-level changes and should be reviewed before execution. The project:

- validates immutable bootstrap archives with SHA-256;
- never stores authentication tokens, passwords, passphrases, or private keys;
- preserves user configuration outside managed sections;
- keeps inspection modes read-only;
- generates sanitized diagnostic bundles;
- pins GitHub Actions to commit SHAs;
- scans committed text for common high-confidence secret formats.
