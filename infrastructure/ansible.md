# Ansible Guidelines

## Design Principles

- Follow idempotent design principles for all playbooks
- Organize playbooks, roles, and inventory using best practices
- Use group_vars and host_vars for environment-specific configurations
- Use roles for modular and reusable configurations
- Validate all playbooks with ansible-lint before running
- Use handlers to avoid unnecessary restarts

## Security & Variables

- Apply variables securely using Ansible Vault for sensitive data
- Use dynamic inventory for cloud environments (e.g., AWS EC2 dynamic inventory)
- Implement tags for flexible task execution
- Leverage Jinja2 templates for dynamic configuration generation
- Never store secrets in plain text
- Use proper file permissions and ownership

## Error Handling & Flow Control

- Use block: / rescue: / always: for structured error handling
- Use delegate_to for remote task execution
- Implement proper retry logic and timeout handling
- Use conditionals (when:) to control task execution
- Implement proper fact gathering and caching

## Best Practices

### Playbook Organization

- Use clear, descriptive names for plays and tasks
- Group related tasks into roles
- Use proper directory structure for complex projects
- Document playbooks and roles with README files
- Use version control for all Ansible code

### Performance Optimization

- Use parallelism and forks appropriately
- Implement proper fact caching
- Use async tasks for long-running operations
- Minimize unnecessary task execution with conditionals
- Use proper connection methods and settings

### Testing & Validation

- Test playbooks in development environments first
- Use Ansible Vault for secrets management
- Implement proper backup procedures before changes
- Use check mode for dry runs
- Validate configuration files before deployment

## Inventory Management

- Use dynamic inventory where possible
- Organize hosts into logical groups
- Use group variables for shared configuration
- Document inventory structure and conventions
- Implement proper naming conventions for hosts and groups
