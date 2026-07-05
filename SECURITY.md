# Security Policy

Report suspected vulnerabilities privately through GitHub's security-advisory interface. Do not open a public issue containing credentials, private session content, exploitable paths, or proof-of-concept secrets.

The audit engine must never retain prompt text, command arguments, credentials, or secret-bearing file contents in results. Changes that expand filesystem access, session-history processing, external writes, or destructive proposals require explicit tests and documentation.

## Security boundaries

- Session-history scanning is opt-in.
- External symlink targets are excluded unless explicitly allowed.
- Static screening never executes audited resources or performs network requests.
- Reports redact known local roots, but canonical local state remains sensitive and should not be published.
- Security findings are heuristic and do not constitute malware certification.
