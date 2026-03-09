"""Alexa Smart Home skill handler that proxies requests to Home Assistant.

Based on https://github.com/home-assistant/alexa-smarthome
"""

import json
import logging
import os

import urllib3

_debug = bool(os.environ.get("DEBUG"))

_logger = logging.getLogger("HomeAssistant-SmartHome")
_logger.setLevel(logging.DEBUG if _debug else logging.INFO)


def lambda_handler(event, context):
    """Handle incoming Alexa directive."""
    _logger.debug("Event: %s", event)

    base_url = os.environ.get("BASE_URL")
    assert base_url is not None, "Please set BASE_URL environment variable"
    base_url = base_url.strip("/")

    directive = event.get("directive")
    assert directive is not None, "Malformatted request - missing directive"
    assert directive.get("header", {}).get("payloadVersion") == "3", \
        "Only support payloadVersion == 3"

    scope = directive.get("endpoint", {}).get("scope")
    if scope is None:
        scope = directive.get("payload", {}).get("grantee")
    if scope is None:
        scope = directive.get("payload", {}).get("scope")
    assert scope is not None, "Malformatted request - missing endpoint.scope"
    assert scope.get("type") == "BearerToken", "Only support BearerToken"

    token = scope.get("token")
    if token is None and _debug:
        token = os.environ.get("LONG_LIVED_ACCESS_TOKEN")

    verify_ssl = not bool(os.environ.get("NOT_VERIFY_SSL"))

    http = urllib3.PoolManager(
        cert_reqs="CERT_REQUIRED" if verify_ssl else "CERT_NONE",
        timeout=urllib3.Timeout(connect=2.0, read=10.0),
    )

    response = http.request(
        "POST",
        f"{base_url}/api/alexa/smart_home",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        body=json.dumps(event).encode("utf-8"),
    )

    if response.status >= 400:
        return {
            "event": {
                "payload": {
                    "type": "INVALID_AUTHORIZATION_CREDENTIAL"
                    if response.status in (401, 403)
                    else "INTERNAL_ERROR",
                    "message": response.data.decode("utf-8"),
                }
            }
        }

    _logger.debug("Response: %s", response.data.decode("utf-8"))
    return json.loads(response.data.decode("utf-8"))
