"""Alexa Custom Skill handler that proxies requests to the garrison crier.

Alexa only invokes this function for the configured skill id; the crier
checks the bearer and skill id again and does all the work.
"""

import json
import logging
import os
import urllib.error
import urllib.request

_debug = bool(os.environ.get("DEBUG"))

_logger = logging.getLogger("garrison-crier")
_logger.setLevel(logging.DEBUG if _debug else logging.INFO)


def _speak(text):
    return {
        "version": "1.0",
        "response": {
            "outputSpeech": {"type": "PlainText", "text": text},
            "shouldEndSession": True,
        },
    }


def lambda_handler(event, context):
    """Forward the Alexa request to the crier and return its response."""
    _logger.debug("Event: %s", event)

    base_url = os.environ["CRIER_URL"].rstrip("/")
    request = urllib.request.Request(
        f"{base_url}/alexa",
        data=json.dumps(event).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {os.environ['CRIER_TOKEN']}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=7) as response:
            body = response.read().decode("utf-8")
    except urllib.error.HTTPError as error:
        _logger.error("crier answered %s: %s", error.code, error.read().decode("utf-8"))
        return _speak("The garrison crier refused that request.")
    except (urllib.error.URLError, TimeoutError) as error:
        _logger.error("crier unreachable: %s", error)
        return _speak("I can't reach the garrison right now.")

    _logger.debug("Response: %s", body)
    return json.loads(body)
