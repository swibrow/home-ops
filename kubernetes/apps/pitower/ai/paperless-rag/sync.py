"""Mirror Paperless-ngx documents into an Open-WebUI knowledge base.

Paperless has already OCR'd every document, so what gets synced is the text it
extracted, wrapped in a metadata header, as one markdown file per document.
Open-WebUI chunks and embeds each file (through LiteLLM, so the embedding model
is swappable there) and stores the vectors in pgvector.

Every run also asserts the Open-WebUI side of the setup, because those settings
are persisted in its database and ignore env vars after first boot:
  - the embedding engine/model the knowledge base is built with
  - retrieval settings (hybrid search, top-k)
  - the "paperless" workspace model, pinned to the local chat model with the
    knowledge base attached

Only the standard library is used so the job runs on a stock python image.
"""

import hashlib
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

PAPERLESS_URL = os.environ["PAPERLESS_URL"].rstrip("/")
PAPERLESS_TOKEN = os.environ["PAPERLESS_TOKEN"]
OPEN_WEBUI_URL = os.environ["OPEN_WEBUI_URL"].rstrip("/")
OPEN_WEBUI_API_KEY = os.environ["OPEN_WEBUI_API_KEY"]
EMBEDDING_BASE_URL = os.environ["EMBEDDING_BASE_URL"]
EMBEDDING_API_KEY = os.environ["EMBEDDING_API_KEY"]
EMBEDDING_MODEL = os.environ["EMBEDDING_MODEL"]
CHAT_MODEL = os.environ["CHAT_MODEL"]
KNOWLEDGE_NAME = os.environ.get("KNOWLEDGE_NAME", "Paperless")
WORKSPACE_MODEL_ID = os.environ.get("WORKSPACE_MODEL_ID", "paperless")
# Paperless' public URL, used for the source link in each document header.
PAPERLESS_PUBLIC_URL = os.environ.get("PAPERLESS_PUBLIC_URL", PAPERLESS_URL).rstrip("/")

FILENAME_PREFIX = "paperless-"


def log(msg):
    print(msg, flush=True)


def http(method, url, headers, body=None, content_type=None, timeout=600):
    data = None
    if body is not None:
        if isinstance(body, (bytes, bytearray)):
            data = bytes(body)
        else:
            data = json.dumps(body).encode()
            content_type = content_type or "application/json"
    req = urllib.request.Request(url, data=data, method=method, headers=dict(headers))
    if content_type:
        req.add_header("Content-Type", content_type)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        raise RuntimeError(f"{method} {url} -> {e.code}: {detail}") from None
    if not raw:
        return None
    return json.loads(raw)


# --- Paperless ---------------------------------------------------------------

PAPERLESS_HEADERS = {"Authorization": f"Token {PAPERLESS_TOKEN}", "Accept": "application/json"}


def paperless_get_all(path, params=None):
    params = {"page_size": 100, **(params or {})}
    url = f"{PAPERLESS_URL}{path}?{urllib.parse.urlencode(params)}"
    results = []
    while url:
        page = http("GET", url, PAPERLESS_HEADERS)
        results.extend(page["results"])
        url = page.get("next")
    return results


def paperless_names(path):
    return {item["id"]: item["name"] for item in paperless_get_all(path)}


def render_document(doc, correspondents, document_types, tags):
    header = [
        f"# {doc['title']}",
        "",
        f"- Paperless ID: {doc['id']}",
        f"- Source: {PAPERLESS_PUBLIC_URL}/documents/{doc['id']}/details",
    ]
    if doc.get("created"):
        header.append(f"- Date: {doc['created'][:10]}")
    if doc.get("correspondent") in correspondents:
        header.append(f"- Correspondent: {correspondents[doc['correspondent']]}")
    if doc.get("document_type") in document_types:
        header.append(f"- Document type: {document_types[doc['document_type']]}")
    doc_tags = [tags[t] for t in doc.get("tags", []) if t in tags]
    if doc_tags:
        header.append(f"- Tags: {', '.join(doc_tags)}")
    if doc.get("archive_serial_number") is not None:
        header.append(f"- Archive serial number: {doc['archive_serial_number']}")
    if doc.get("original_file_name"):
        header.append(f"- Original file: {doc['original_file_name']}")
    body = (doc.get("content") or "").strip()
    return "\n".join(header) + "\n\n" + body + "\n"


# --- Open-WebUI --------------------------------------------------------------

OWUI_HEADERS = {"Authorization": f"Bearer {OPEN_WEBUI_API_KEY}", "Accept": "application/json"}


def owui(method, path, body=None, **kw):
    return http(method, f"{OPEN_WEBUI_URL}{path}", OWUI_HEADERS, body, **kw)


def ensure_embedding_config():
    """Returns True when the embedding setup changed, which invalidates every
    vector already stored for the knowledge base."""
    current = owui("GET", "/api/v1/retrieval/embedding")
    desired = {
        "RAG_EMBEDDING_ENGINE": "openai",
        "RAG_EMBEDDING_MODEL": EMBEDDING_MODEL,
        "RAG_EMBEDDING_BATCH_SIZE": 16,
        "ENABLE_ASYNC_EMBEDDING": True,
        "RAG_EMBEDDING_CONCURRENT_REQUESTS": 0,
        "openai_config": {"url": EMBEDDING_BASE_URL, "key": EMBEDDING_API_KEY},
    }
    unchanged = all(current.get(k) == v for k, v in desired.items())
    if unchanged:
        return False
    log(f"embedding config: {current.get('RAG_EMBEDDING_ENGINE')!r}/{current.get('RAG_EMBEDDING_MODEL')!r}"
        f" -> openai/{EMBEDDING_MODEL}")
    owui("POST", "/api/v1/retrieval/embedding/update", desired)
    return True


def ensure_retrieval_config():
    current = owui("GET", "/api/v1/retrieval/config")
    # BM25 alongside the vector search: invoice numbers, names and amounts are
    # exact tokens an embedding alone ranks poorly. Without a reranker
    # Open-WebUI falls back to cosine scoring for the fused results.
    desired = {"ENABLE_RAG_HYBRID_SEARCH": True, "TOP_K": 5}
    if all(current.get(k) == v for k, v in desired.items()):
        return
    log(f"retrieval config -> {desired}")
    owui("POST", "/api/v1/retrieval/config/update", desired)


def ensure_knowledge():
    page = 1
    while True:
        listing = owui("GET", f"/api/v1/knowledge/?page={page}")
        for kb in listing["items"]:
            if kb["name"] == KNOWLEDGE_NAME:
                return kb
        if len(listing["items"]) == 0 or page * 30 >= listing["total"]:
            break
        page += 1
    log(f"creating knowledge base {KNOWLEDGE_NAME!r}")
    # No access grants: private to the API key's user, like the documents.
    return owui("POST", "/api/v1/knowledge/create", {
        "name": KNOWLEDGE_NAME,
        "description": "Documents mirrored from Paperless-ngx by the paperless-rag sync job.",
        "access_grants": [],
    })


def knowledge_files(kb_id):
    """paperless id -> {file_id, hash} for every file the sync job uploaded."""
    files = {}
    page = 1
    while True:
        listing = owui("GET", f"/api/v1/knowledge/{kb_id}/files?page={page}&limit=500")
        for f in listing["items"]:
            name = (f.get("meta") or {}).get("name") or f.get("filename") or ""
            if not name.startswith(FILENAME_PREFIX):
                continue
            pid = int(name[len(FILENAME_PREFIX):].split(".")[0])
            files[pid] = {"file_id": f["id"], "hash": (f.get("meta") or {}).get("file_hash")}
        if len(listing["items"]) < 500:
            return files
        page += 1


def upload_document(kb_id, pid, content):
    boundary = uuid.uuid4().hex
    filename = f"{FILENAME_PREFIX}{pid}.md"
    metadata = json.dumps({"knowledge_id": kb_id, "paperless_id": pid})
    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="metadata"\r\n\r\n{metadata}\r\n'
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{filename}"\r\n'
        f"Content-Type: text/markdown\r\n\r\n"
    ).encode() + content + f"\r\n--{boundary}--\r\n".encode()
    # Synchronous: the file is extracted, embedded and linked to the knowledge
    # base before the call returns, so a failure surfaces here, not in a log.
    result = owui("POST", "/api/v1/files/?process=true&process_in_background=false",
                  body, content_type=f"multipart/form-data; boundary={boundary}")
    status = (result.get("data") or {}).get("status")
    if status == "failed":
        raise RuntimeError(f"processing failed for {filename}: {(result.get('data') or {}).get('error')}")
    return result["id"]


def remove_file(kb_id, file_id):
    owui("POST", f"/api/v1/knowledge/{kb_id}/file/remove?delete_file=true", {"file_id": file_id})


def ensure_workspace_model(kb):
    """A chat entry that always answers from the knowledge base with the local
    model, so a question never silently goes to a hosted model."""
    knowledge_ref = {"id": kb["id"], "name": kb["name"], "type": "collection"}
    form = {
        "id": WORKSPACE_MODEL_ID,
        "base_model_id": CHAT_MODEL,
        "name": KNOWLEDGE_NAME,
        "meta": {
            "description": f"Answers from the {KNOWLEDGE_NAME} documents using {CHAT_MODEL}.",
            "knowledge": [knowledge_ref],
        },
        # legacy = retrieval is injected into every turn; native tool calling
        # would leave it to the model to decide whether to search.
        "params": {"function_calling": "legacy"},
        "access_grants": [],
    }
    try:
        current = owui("GET", f"/api/v1/models/model?id={urllib.parse.quote(WORKSPACE_MODEL_ID)}")
    except RuntimeError as e:
        if "-> 404" not in str(e):
            raise
        current = None
    if current is None:
        log(f"creating workspace model {WORKSPACE_MODEL_ID!r}")
        owui("POST", "/api/v1/models/create", form)
        return
    meta = current.get("meta") or {}
    in_sync = (
        current.get("base_model_id") == CHAT_MODEL
        and [k.get("id") for k in (meta.get("knowledge") or [])] == [kb["id"]]
        and (current.get("params") or {}).get("function_calling") == "legacy"
    )
    if in_sync:
        return
    log(f"updating workspace model {WORKSPACE_MODEL_ID!r}")
    owui("POST", f"/api/v1/models/model/update?id={urllib.parse.quote(WORKSPACE_MODEL_ID)}", form)


# --- Sync --------------------------------------------------------------------

def main():
    embedding_changed = ensure_embedding_config()
    ensure_retrieval_config()
    kb = ensure_knowledge()
    if embedding_changed:
        log("embedding model changed: resetting knowledge base so every document is re-embedded")
        owui("POST", f"/api/v1/knowledge/{kb['id']}/reset")

    existing = knowledge_files(kb["id"])
    correspondents = paperless_names("/api/correspondents/")
    document_types = paperless_names("/api/document_types/")
    tags = paperless_names("/api/tags/")
    docs = paperless_get_all("/api/documents/", {
        "ordering": "id",
        "fields": "id,title,content,created,correspondent,document_type,tags,"
                  "archive_serial_number,original_file_name",
    })
    log(f"paperless: {len(docs)} documents; knowledge base: {len(existing)} files")

    added = updated = unchanged = 0
    seen = set()
    for doc in docs:
        pid = doc["id"]
        seen.add(pid)
        content = render_document(doc, correspondents, document_types, tags).encode()
        digest = hashlib.sha256(content).hexdigest()
        current = existing.get(pid)
        if current and current["hash"] == digest:
            unchanged += 1
            continue
        if current:
            remove_file(kb["id"], current["file_id"])
            updated += 1
        else:
            added += 1
        upload_document(kb["id"], pid, content)
        log(f"{'updated' if current else 'added'} {pid}: {doc['title']}")

    removed = 0
    for pid, current in existing.items():
        if pid not in seen:
            remove_file(kb["id"], current["file_id"])
            removed += 1
            log(f"removed {pid}")

    ensure_workspace_model(kb)
    log(f"done: {added} added, {updated} updated, {removed} removed, {unchanged} unchanged")


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as e:
        log(f"error: {e}")
        sys.exit(1)
