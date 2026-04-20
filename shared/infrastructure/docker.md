# Docker Standards

## Dockerfile Guidelines

- Use multi-stage builds to reduce image size and separate build/runtime concerns
- Always specify a fixed image version/tag (e.g., python:3.11-slim, not latest)
- Set WORKDIR early and use absolute paths consistently
- Use COPY over ADD unless specific features (e.g., remote URL or auto-extract) are required
- Group related RUN commands using && \\ and minimize layers for efficiency
- Format multiline commands with backslash at the end of one line and '&&' at the start of the next line for readability
- Avoid installing unnecessary packages; clean up temporary files and package manager caches
- Do not pin apt package versions when installing packages (for flexibility)
- Use CMD for the default command and ENTRYPOINT only when overriding behavior is intended
- Do not run processes as root; use non-root users (USER) where feasible
- Label images using LABEL for metadata (org.opencontainers.image.*)
- Validate Dockerfiles with hadolint and maintain consistency with team standards
- Add health checks (HEALTHCHECK) where appropriate for container lifecycle monitoring
- Avoid including healthcheck comments in Dockerfiles for cleaner code

## Security Best Practices

- Use official base images from trusted sources
- Regularly update base images to include security patches
- Use specific version tags rather than latest
- Run containers with non-root users
- Use .dockerignore to exclude sensitive files
- Scan images for vulnerabilities before deployment
- Avoid Docker-in-Docker patterns for security reasons
- Prefer using own compute resources over paid cloud services for cost and security

## Multi-Stage Build Patterns

- Separate build dependencies from runtime dependencies
- Use builder stages for compiling code
- Copy only necessary artifacts to final stage
- Use appropriate base images for each stage
- Optimize layer caching for faster builds

## Container Optimization

- Minimize image size by removing unnecessary files
- Use appropriate base images (alpine, slim, distroless)
- Leverage Docker layer caching effectively
- Use multi-architecture builds where needed
- Implement proper logging and monitoring

## Development Workflow

- Build and test images locally before pushing
- Use consistent tagging strategies
- Implement proper CI/CD integration
- Use container registries securely
- Monitor container performance and resource usage

## Dependency Management

- Lockfiles are the source of truth for versions; Dockerfile versions should match the corresponding lockfile
- Packages in Dockerfiles should not be too old and should match (or be similar to) versions specified in project lockfiles for each language
- Ensure version consistency between Dockerfiles and package management files
