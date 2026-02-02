# syntax=docker/dockerfile:1
# Builds the quickstart backend container image and configures scripts/install-prerequisites.sh and scripts/build.sh
# as the entrypoint used both locally and when deployed via Docker.
FROM swift:5.9-jammy

ENV APP_HOME=/workspace \
    RUN_MODE=container

WORKDIR /app

COPY . .

# Provide APP_START_CMD via --env-file.
CMD ["bash", "scripts/build.sh"]
