#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 The rpki-selflab authors
"""Simulated registry (RIR/NIR) panel for the lab.

Plays the role a real registry's panel plays: shows the resources allocated
to the holder, and for whoever opts for delegated RPKI, receives the child
CA's identity and hands back the parent's response - and the same for the
publication service.

Underneath, it talks to the RIR's Krill (lab-rir container) through krillc.
krillc already knows how to read the RFC 8183 XML and write the response, so
there's no certificate handling of any kind in here.
"""

import json
import os
import re
import subprocess
import ssl
import urllib.parse
import urllib.request
import socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LAB_CONF = "/lab/lab.conf"
RIR_CONTAINER = os.environ.get("RIR_CONTAINER", "lab-rir")
RIR_CA = os.environ.get("RIR_CA", "testbed")
RIR_URL = os.environ.get("RIR_URL", "https://rir.lab:3000")
CA_PEM = "/pki/ca.pem"
PORT = int(os.environ.get("PORT", "8081"))
HERE = os.path.dirname(os.path.abspath(__file__))

LANGUAGES = ("pt", "es", "en")


# ---------------------------------------------------------------------------
# Message catalog
#
# Only this panel's own messages live here. Krill's native error messages
# (parsed out by clean_error, below) stay in whatever language Krill itself
# produced them in - usually English - since translating a third party's
# error text isn't something this file controls.
# ---------------------------------------------------------------------------
MESSAGES = {
    "cant_reach": {
        "pt": "não consegui falar com o {c}: {e}",
        "es": "no pude hablar con {c}: {e}",
        "en": "couldn't talk to {c}: {e}",
    },
    "unknown_error": {
        "pt": "erro desconhecido",
        "es": "error desconocido",
        "en": "unknown error",
    },
    "not_a_child_request": {
        "pt": ("Isto não parece um <child_request>. Copie o XML inteiro "
               "do seu Krill, em CAs-pai → Requisição da CA-Filha."),
        "es": ("Esto no parece un <child_request>. Copie el XML completo "
               "de su Krill, en CAs-padre → Solicitud de la CA-Hija."),
        "en": ("This doesn't look like a <child_request>. Copy the whole XML "
               "from your Krill, under Parent CAs → Child Request."),
    },
    "not_a_publisher_request": {
        "pt": ("Isto não parece um <publisher_request>. Copie o XML "
               "inteiro do seu Krill, em Repositório → Requisição do "
               "Publicador."),
        "es": ("Esto no parece un <publisher_request>. Copie el XML "
               "completo de su Krill, en Repositorio → Solicitud del "
               "Publicador."),
        "en": ("This doesn't look like a <publisher_request>. Copy the "
               "whole XML from your Krill, under Repository → Publisher "
               "Request."),
    },
    "no_delegated_ca_to_revoke": {
        "pt": "Não há nenhuma CA delegada para revogar.",
        "es": "No hay ninguna CA delegada para revocar.",
        "en": "There's no delegated CA to revoke.",
    },
    "delegation_revoked": {
        "pt": "Delegação revogada.",
        "es": "Delegación revocada.",
        "en": "Delegation revoked.",
    },
    "no_delegated_ca": {
        "pt": "Nenhuma CA delegada.",
        "es": "Ninguna CA delegada.",
        "en": "No delegated CA.",
    },
    "no_publication_to_revoke": {
        "pt": "Não há nenhuma publicação autorizada para revogar.",
        "es": "No hay ninguna publicación autorizada para revocar.",
        "en": "There's no authorized publication to revoke.",
    },
    "publication_revoked": {
        "pt": "Publicação revogada.",
        "es": "Publicación revocada.",
        "en": "Publication revoked.",
    },
    "no_authorized_publication": {
        "pt": "Nenhuma publicação autorizada.",
        "es": "Ninguna publicación autorizada.",
        "en": "No authorized publication.",
    },
    "not_found": {
        "pt": "não encontrado",
        "es": "no encontrado",
        "en": "not found",
    },
    "tal_fetch_failed": {
        "pt": "não consegui buscar o TAL: {e}",
        "es": "no pude descargar el TAL: {e}",
        "en": "couldn't fetch the TAL: {e}",
    },
    "server_up": {
        "pt": "painel do registro em http://0.0.0.0:{port}",
        "es": "panel del registro en http://0.0.0.0:{port}",
        "en": "registry panel at http://0.0.0.0:{port}",
    },
}


def t(language, key, **kw):
    language = language if language in LANGUAGES else "pt"
    template = MESSAGES[key].get(language, MESSAGES[key]["pt"])
    return template.format(**kw) if kw else template


# ---------------------------------------------------------------------------
# lab.conf
# ---------------------------------------------------------------------------
def read_conf():
    """Reads lab.conf on every call: editing the file reflects instantly."""
    data = {}
    try:
        with open(LAB_CONF) as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if "=" in line:
                    key, value = line.split("=", 1)
                    data[key.strip()] = value.strip().strip('"').strip("'")
    except OSError:
        pass
    return data


DEFAULT_LANGUAGE = read_conf().get("LANGUAGE", "pt")
if DEFAULT_LANGUAGE not in LANGUAGES:
    DEFAULT_LANGUAGE = "pt"


# ---------------------------------------------------------------------------
# krillc inside the RIR container
# ---------------------------------------------------------------------------
def krillc(*args, xml=None, file="/tmp/req.xml", language=DEFAULT_LANGUAGE):
    """Runs krillc inside lab-rir. Returns (ok, output)."""
    if xml is not None:
        written = subprocess.run(
            ["docker", "exec", "-i", RIR_CONTAINER, "sh", "-c", f"cat > {file}"],
            input=xml.encode(), capture_output=True, timeout=20,
        )
        if written.returncode != 0:
            return False, written.stderr.decode("utf-8", "replace")
    try:
        p = subprocess.run(
            ["docker", "exec", RIR_CONTAINER, "krillc", *args],
            capture_output=True, timeout=60,
        )
    except Exception as e:                                    # noqa: BLE001
        return False, t(language, "cant_reach", c=RIR_CONTAINER, e=e)
    output = (p.stdout + p.stderr).decode("utf-8", "replace").strip()
    return p.returncode == 0, output


def resources():
    c = read_conf()
    return c.get("ORIGIN_ASN", ""), c.get("ORIGIN_V4", ""), c.get("ORIGIN_V6", "")


def attribute_from_xml(xml, attribute):
    m = re.search(rf'{attribute}="([^"]+)"', xml)
    return m.group(1) if m else None


def clean_error(output, language=DEFAULT_LANGUAGE):
    """Turns Krill's error message into something readable for the class.

    Krill's own "msg" field is left as Krill produced it (in practice,
    English) - this panel doesn't try to translate a third party's text.
    """
    m = re.search(r'"msg":"([^"]+)"', output)
    if m:
        return m.group(1)
    return output.splitlines()[0] if output else t(language, "unknown_error")


# ---------------------------------------------------------------------------
# Holder's state at the registry
# ---------------------------------------------------------------------------
def children():
    """Lists the registered child CAs, with the latest Up-Down exchange."""
    ok, output = krillc("children", "connections", "--ca", RIR_CA)
    if not ok:
        return []
    lines = [l for l in output.splitlines() if l.strip()]
    result = []
    for line in lines[1:]:                        # first line is the header
        parts = line.split(",")
        if len(parts) >= 5:
            result.append({
                "handle": parts[0],
                "agent": parts[1],
                "last_exchange": parts[2],
                "result": parts[3],
                "state": parts[4],
            })
    return result


def publishers():
    ok, output = krillc("pubserver", "publishers", "list")
    if not ok:
        return []
    m = re.search(r"Publishers:\s*(.*)", output)
    if not m:
        return []
    internal = {"ta", RIR_CA}
    return [p.strip() for p in m.group(1).split(",")
            if p.strip() and p.strip() not in internal]


def publisher_detail(handle):
    ok, output = krillc("pubserver", "publishers", "show", "--publisher", handle)
    if not ok:
        return None
    objects = [l.strip() for l in output.splitlines() if l.strip().startswith("rsync://")]
    by_type = {}
    for o in objects:
        ext = o.rsplit(".", 1)[-1] if "." in o else "?"
        by_type[ext] = by_type.get(ext, 0) + 1
    return {"objects": len(objects), "by_type": by_type, "list": objects[:40]}


def state():
    c = read_conf()
    asn, v4, v6 = resources()
    child_list = children()
    publisher_list = publishers()
    detail = publisher_detail(publisher_list[0]) if publisher_list else None
    return {
        "registry": {
            "name": c.get("RIR_NAME", "LabNIC"),
            "description": c.get("RIR_DESCRIPTION", "Laboratory Internet registry"),
            "ca": RIR_CA,
            "url": RIR_URL,
        },
        "holder": {
            "name": c.get("HOLDER_NAME", "Lab holder"),
            "document": c.get("HOLDER_DOC", ""),
            "handle": c.get("HOLDER_HANDLE", ""),
        },
        "resources": {
            "asn": asn,
            "v4": v4,
            "v6": v6,
            "v4_maxlen": c.get("ORIGIN_V4_MAXLEN", ""),
            "v6_maxlen": c.get("ORIGIN_V6_MAXLEN", ""),
        },
        "language": c.get("LANGUAGE", "pt"),
        "delegation": child_list[0] if child_list else None,
        "publication": ({"handle": publisher_list[0], **(detail or {})} if publisher_list else None),
        "rrdp": f"{RIR_URL}/rrdp/notification.xml",
        "tal": f"{RIR_URL}/ta/ta.tal",
    }


# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------
def issue_certificate(xml, language=DEFAULT_LANGUAGE):
    handle = attribute_from_xml(xml, "child_handle")
    if not handle:
        return False, t(language, "not_a_child_request")
    asn, v4, v6 = resources()
    args = ["children", "add", "--ca", RIR_CA, "--child", handle,
            "--request", "/tmp/req.xml"]
    if asn:
        args += ["--asn", asn]
    if v4:
        args += ["--ipv4", v4]
    if v6:
        args += ["--ipv6", v6]
    ok, output = krillc(*args, xml=xml, language=language)
    if not ok:
        # already exists? hand back the response that's actually in effect,
        # instead of a plain error
        if "already" in output or "duplicate" in output:
            ok2, resp = krillc("children", "response", "--ca", RIR_CA,
                               "--child", handle, language=language)
            if ok2:
                return True, resp
        return False, clean_error(output, language)
    return True, output


def revoke_certificate(language=DEFAULT_LANGUAGE):
    child_list = children()
    if not child_list:
        return False, t(language, "no_delegated_ca_to_revoke")
    ok, output = krillc("children", "remove", "--ca", RIR_CA,
                        "--child", child_list[0]["handle"], language=language)
    return (True, t(language, "delegation_revoked")) if ok else (False, clean_error(output, language))


def authorize_publication(xml, language=DEFAULT_LANGUAGE):
    handle = attribute_from_xml(xml, "publisher_handle")
    if not handle:
        return False, t(language, "not_a_publisher_request")
    ok, output = krillc("pubserver", "publishers", "add",
                        "--request", "/tmp/req.xml", xml=xml, language=language)
    if not ok:
        if "already" in output or "duplicate" in output:
            ok2, resp = krillc("pubserver", "publishers", "response",
                               "--publisher", handle, language=language)
            if ok2:
                return True, resp
        return False, clean_error(output, language)
    return True, output


def revoke_publication(language=DEFAULT_LANGUAGE):
    publisher_list = publishers()
    if not publisher_list:
        return False, t(language, "no_publication_to_revoke")
    ok, output = krillc("pubserver", "publishers", "remove",
                        "--publisher", publisher_list[0], language=language)
    return (True, t(language, "publication_revoked")) if ok else (False, clean_error(output, language))


def delegation_response(language=DEFAULT_LANGUAGE):
    child_list = children()
    if not child_list:
        return False, t(language, "no_delegated_ca")
    return krillc("children", "response", "--ca", RIR_CA,
                  "--child", child_list[0]["handle"], language=language)


def publication_response(language=DEFAULT_LANGUAGE):
    publisher_list = publishers()
    if not publisher_list:
        return False, t(language, "no_authorized_publication")
    return krillc("pubserver", "publishers", "response",
                  "--publisher", publisher_list[0], language=language)


def download_tal():
    ctx = ssl.create_default_context(cafile=CA_PEM)
    with urllib.request.urlopen(f"{RIR_URL}/ta/ta.tal", timeout=10, context=ctx) as r:
        return r.read()


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

class DualStackServer(ThreadingHTTPServer):
    """Listens on IPv6 and IPv4 at once (::), so localhost works both ways."""
    address_family = socket.AF_INET6

    def server_bind(self):
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        super().server_bind()


class Panel(BaseHTTPRequestHandler):
    server_version = "LabNIC"

    def log_message(self, *a):                                # less noise
        pass

    def _language(self):
        qs = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query)
        lang = (qs.get("lang") or [DEFAULT_LANGUAGE])[0]
        return lang if lang in LANGUAGES else DEFAULT_LANGUAGE

    def _send(self, status, body, content_type="application/json; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, data, status=200):
        self._send(status, json.dumps(data, ensure_ascii=False))

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n).decode("utf-8", "replace")

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        language = self._language()
        if path in ("/", "/index.html"):
            with open(os.path.join(HERE, "panel.html"), "rb") as f:
                return self._send(200, f.read(), "text/html; charset=utf-8")
        if path == "/language.js":
            with open(os.path.join(HERE, "language.js"), "rb") as f:
                return self._send(200, f.read(), "text/javascript; charset=utf-8")
        if path == "/api/state":
            return self._json(state())
        if path == "/api/delegation/response":
            ok, output = delegation_response(language)
            return self._json({"ok": ok, "response" if ok else "error": output},
                              200 if ok else 400)
        if path == "/api/publication/response":
            ok, output = publication_response(language)
            return self._json({"ok": ok, "response" if ok else "error": output},
                              200 if ok else 400)
        if path == "/ta.tal":
            try:
                return self._send(200, download_tal(), "text/plain; charset=utf-8")
            except Exception as e:                            # noqa: BLE001
                return self._send(502, t(language, "tal_fetch_failed", e=e),
                                   "text/plain; charset=utf-8")
        return self._send(404, t(language, "not_found"), "text/plain; charset=utf-8")

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        language = self._language()
        if path == "/api/delegation":
            ok, output = issue_certificate(self._body(), language)
        elif path == "/api/publication":
            ok, output = authorize_publication(self._body(), language)
        else:
            return self._send(404, t(language, "not_found"), "text/plain; charset=utf-8")
        return self._json({"ok": ok, "response" if ok else "error": output},
                          200 if ok else 400)

    def do_DELETE(self):
        path = self.path.split("?", 1)[0]
        language = self._language()
        if path == "/api/delegation":
            ok, message = revoke_certificate(language)
        elif path == "/api/publication":
            ok, message = revoke_publication(language)
        else:
            return self._send(404, t(language, "not_found"), "text/plain; charset=utf-8")
        return self._json({"ok": ok, "message" if ok else "error": message},
                          200 if ok else 400)


if __name__ == "__main__":
    print(t(DEFAULT_LANGUAGE, "server_up", port=PORT), flush=True)
    DualStackServer(("::", PORT), Panel).serve_forever()
