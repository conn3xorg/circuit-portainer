"""Uses Portainer the way a person would, through its API.

Signs in as admin, checks a wrong password is refused, lists the host's
containers through the local Podman environment, adds the agent as a second
environment (once) and reads the engine's details through it. Run by check.sh.
"""

import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

base, cert = sys.argv[1], sys.argv[2]
password = os.environ.get("PORTAINER_PASSWORD", "example-password-not-secret")

# Trust Portainer's own certificate and nothing else. It names no host we
# can match, so the name check is off; the certificate itself is checked.
ctx = ssl.create_default_context(cafile=cert)
ctx.check_hostname = False
ctx.verify_flags |= ssl.VERIFY_X509_PARTIAL_CHAIN


def call(method, path, body=None, token=None, form=False):
    headers = {}
    data = None
    if token:
        headers["Authorization"] = "Bearer " + token
    if body is not None:
        if form:
            data = urllib.parse.urlencode(body).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            data = json.dumps(body).encode()
            headers["Content-Type"] = "application/json"
    req = urllib.request.Request(base + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=30) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


# Portainer may still be starting after a restart.
for _ in range(60):
    try:
        status, _ = call("GET", "/api/system/status")
        if status == 200:
            break
    except (urllib.error.URLError, ConnectionError, ssl.SSLError):
        pass
    time.sleep(2)
else:
    sys.exit("Portainer didn't answer on " + base)

status, body = call("POST", "/api/auth", {"username": "admin", "password": password + "x"})
assert status in (401, 422), f"a wrong password got {status}"

status, body = call("POST", "/api/auth", {"username": "admin", "password": password})
assert status == 200, f"sign-in failed: {status} {body}"
token = body["jwt"]

status, endpoints = call("GET", "/api/endpoints", token=token)
assert status == 200, f"listing environments failed: {status} {endpoints}"
local = next(e for e in endpoints if e["URL"].startswith("unix://"))

status, containers = call("GET", f"/api/endpoints/{local['Id']}/docker/containers/json?all=1", token=token)
assert status == 200, f"listing containers failed: {status} {containers}"
names = {n for c in containers for n in c["Names"]}
assert "/portainer" in names and "/portainer-agent" in names, f"containers seen through Podman: {names}"
print(f"Signed in; {local['Name']} lists {len(containers)} containers, Portainer's own among them.")

agent = next((e for e in endpoints if e["Name"] == "agent"), None)
if agent is None:
    status, agent = call(
        "POST",
        "/api/endpoints",
        {
            "Name": "agent",
            "EndpointCreationType": "2",
            "URL": "tcp://127.0.0.1:9001",
            "TLS": "true",
            "TLSSkipVerify": "true",
            "TLSSkipClientVerify": "true",
        },
        token=token,
        form=True,
    )
    assert status == 200, f"adding the agent failed: {status} {agent}"
    print("Added the agent as an environment.")

status, info = call("GET", f"/api/endpoints/{agent['Id']}/docker/info", token=token)
assert status == 200, f"reading the engine through the agent failed: {status} {info}"
assert info.get("Containers", 0) >= 2, f"the agent saw {info.get('Containers')} containers"
print(f"The agent answers for {info.get('Name')}, with {info['Containers']} containers.")
