# Bash Scripting Standards

## Quality Standards

- Scripts should pass shellcheck linting
- Use descriptive names for scripts and variables (e.g., backup_files.sh, log_rotation.sh)
- Write modular scripts with functions to enhance readability and reuse
- Include comments for each major section or function
- Validate all inputs using getopts or manual validation logic

## Best Practices

- Avoid hardcoding; use environment variables or parameterized inputs
- Ensure portability by using POSIX-compliant syntax
- Redirect output to log files where appropriate, separating stdout and stderr
- Use trap for error handling and clean-up
- Secure automation (e.g., use SSH with key-based auth for SCP/SFTP)
- Schedule tasks using cron securely (avoid writing secrets in crontab)

## Code Structure

- Follow best practices for bash scripting
- Avoid inline comments unless necessary
- Prefer colors in scripts for readability
- Use proper quoting and variable expansion
- Implement proper error handling with set -e and set -u where appropriate

## Security Considerations

- Never hardcode secrets or sensitive data
- Use proper file permissions
- Validate all user inputs
- Use secure methods for remote operations
- Apply principle of least privilege

## Shell Compatibility

- Use appropriate shebang lines (#!/bin/bash vs #!/bin/zsh)
- Test commands in actual shell environment when possible
- Consider cross-shell compatibility for scripts
- Ensure portability by using POSIX-compliant syntax where applicable
