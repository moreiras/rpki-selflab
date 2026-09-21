# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# Simulated registry panel. Stock Python, no external dependency: the lab
# needs to come up without pulling anything beyond the images themselves.
FROM alpine:3.22

RUN apk add --no-cache python3 docker-cli tini

WORKDIR /app
COPY app.py panel.html language.js /app/

EXPOSE 8081
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["python3", "/app/app.py"]
