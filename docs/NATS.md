# internal_docs — NATS subjects (query & retrieval)

The consumer registers these subjects with `BotArmyRuntime.Registry` and heartbeats every 20s. All request-reply bodies are JSON objects (optionally wrapped as `{"payload": ...}` per `BotArmyCore.NATS.Decoder`).

## `internal_docs.query` (request-reply)

Semantic search: the service embeds the query via the LLM embed path, then runs vector similarity over `doc_chunks`. If embedding fails, it falls back to keyword search.

**Request**

| Field   | Type   | Required | Default | Description                                |
|---------|--------|----------|---------|--------------------------------------------|
| `query` | string | yes      | —       | Natural-language query                     |
| `limit` | int    | no       | 5       | Max results                                |

**Response (success)**

| Field      | Type    | Description |
|------------|---------|-------------|
| `ok`       | boolean | `true`      |
| `results`  | array   | Hit list    |
| `count`    | int     | `length(results)` |
| `fallback` | string  | Present only when keyword fallback was used: `"keyword"` |

Each result object:

| Field                | Type   | Description |
|----------------------|--------|-------------|
| `id`                 | uuid   | Chunk id    |
| `source_id`          | uuid   | Source id   |
| `heading`            | string | Section heading |
| `content`            | string | Truncated to 500 characters (or full if shorter) |
| `snippet_chars`      | int    | Length of returned `content` string |
| `chunk_index`        | int    | Order within source |
| `enrichment_status`  | string | e.g. `pending` / `done` |
| `topics`             | list   | Enrichment topics if any |
| `summary`            | string | Enrichment summary if any |

**Response (error)**  
`{"ok": false, "error": "<reason>"}`

**Two-step pattern**  
For full text, call `internal_docs.chunk.get` with the `id` from a query result (see below).

---

## `internal_docs.search` (request-reply)

Full-text / keyword search (Postgres `websearch_to_tsquery` and `ilike`); no embedding.

**Request:** `query` (string, required), `limit` (int, default 10).  
**Response:** same shape as `internal_docs.query` success, without `fallback`.

---

## `internal_docs.chunk.get` (request-reply)

Load a full chunk (or a bounded prefix) and optional neighboring chunks for the same `source_id` (by `chunk_index` range).

**Request**

| Field        | Type   | Required | Default   | Description |
|--------------|--------|----------|-----------|-------------|
| `chunk_id`   | string | yes      | —         | UUID of the chunk |
| `max_chars`  | int    | no       | 200_000   | Cap on returned `content` (hard max 500_000) |
| `before`     | int    | no       | 0         | Neighbor chunks before anchor index (max 5) |
| `after`      | int    | no       | 0         | Neighbor chunks after anchor index (max 5) |

**Response (success)**

- `chunk`: full record for the primary id, including `content` (sliced to `max_chars`), `content_truncated`, `max_chars`, `heading`, `source_id`, `chunk_index`, `enrichment_status`, `topics`, `summary`.
- `neighbors`: when `before` or `after` is greater than zero, adjacent rows; each neighbor includes a short `content` slice (up to 1200 chars) for context.

**Response (error)**  
`{"ok": false, "error": "chunk_id required"}` or `"not_found"`.

---

## Other registered subjects (brief)

| Subject | Mode | Purpose |
|---------|------|---------|
| `internal_docs.source.list` | request-reply | List configured sources |
| `internal_docs.source.add` | request-reply | Add source |
| `internal_docs.source.remove` | request-reply | Remove by `source_id` |
| `internal_docs.source.update` | request-reply | Update by `source_id` |
| `internal_docs.ingest` | request-reply | Trigger fetch/ingest (optionally `source_id`) |
| `events.llm.embedding.created` | subscribe | Embedding callback for ingested chunks |

Embedding callbacks accept chunk identifiers under `chunk_id`, `reference_id`, or legacy `card_id`.

---

## Example: query then expand

```text
# 1) Discover candidates
nats request internal_docs.query '{"query":"how we handle deploys","limit":3}'

# 2) Full text for one hit
nats request internal_docs.chunk.get '{"chunk_id":"<uuid-from-step-1>","max_chars":100000,"before":1,"after":1}'
```
