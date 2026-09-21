# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The lab-aspa authors
# Browser terminal (ttyd) + the lab's state collector.
FROM alpine:3.22

RUN apk add --no-cache ttyd docker-cli docker-cli-compose bash python3 tini curl jq ncurses

COPY menu.sh   /usr/local/bin/menu.sh
COPY status.py /usr/local/bin/status.py
RUN chmod +x /usr/local/bin/menu.sh /usr/local/bin/status.py

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["ttyd", "-6", "-W", "-a", "-p", "7681", "-t", "disableLeaveAlert=true", \
     "-t", "disableReconnect=true", "/usr/local/bin/menu.sh"]
