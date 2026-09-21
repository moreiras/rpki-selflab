# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
# Lab support utilities: generates the internal PKI and fetches the TAL.
# Runs as an init container (executes once and exits).
FROM alpine:3.22
RUN apk add --no-cache openssl curl
COPY generate-pki.sh tal-init.sh i18n.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/generate-pki.sh /usr/local/bin/tal-init.sh
CMD ["/usr/local/bin/generate-pki.sh"]
