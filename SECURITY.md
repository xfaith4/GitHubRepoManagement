# Security Policy

## Supported Scope

Security issues in this repo include:

- credential/token handling,
- command execution safeguards,
- dependency and API host exposure risks,
- artifact/log data leakage.

## Reporting

- Do not open public issues for suspected vulnerabilities.
- Report privately to project maintainers with:
  - reproduction steps,
  - impacted paths/components,
  - severity assessment.

## Secret Handling Baseline

- Use environment variables for secrets.
- Never commit tokens, keys, or credentials.
- Redact sensitive fields from logs and artifacts.
