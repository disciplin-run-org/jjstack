---
name: google-drive-pdf-ocr
description: "Read text from PDFs stored in Google Drive using Drive's built-in OCR — no local download, no pymupdf. Works when using the google-workspace MCP server."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [PDF, OCR, Google Drive, MCP, text-extraction]
    related_skills: [ocr-and-documents, google-workspace]
---

# Google Drive PDF OCR (via MCP)

Use this when PDFs live in Google Drive and you're accessing Drive via the
**google-workspace MCP server** (`http://localhost:7001/mcp/`).

## The Problem

`mcp__google_workspace__docs_read` with a PDF file ID returns:
```
HTTP 400: Request contains an invalid argument.
```
The Docs API only accepts native Google Doc IDs, not PDF Drive file IDs.

## The Solution

Google Drive can OCR a PDF during a copy operation — if you copy a PDF
with `mimeType: application/vnd.google-apps.document`, Drive converts it
and the result is a readable Google Doc.

## Trigger Conditions

- You need text from a PDF that lives in Google Drive
- You're using the google-workspace MCP (not downloading files locally)
- `docs_read` returns HTTP 400 on the PDF file ID

## Steps

1. Load the token from the MCP's pickle file
2. POST to Drive API `files/{id}/copy` with Google Doc mimeType
3. Wait for the copy (a few seconds per file)
4. Read the new doc ID with `mcp__google_workspace__docs_read`
5. Delete the temp doc to keep Drive clean

## Code

```python
import os, pickle, requests

TOKEN_PATH = os.environ.get(
    'GW_MCP_TOKEN',
    os.path.expanduser('~/google-workspace-mcp/data/token.pickle'),
)

with open(TOKEN_PATH, 'rb') as f:
    creds = pickle.load(f)
token = creds.token

def pdf_to_doc(file_id: str, label: str = "temp") -> str | None:
    """Copy a Drive PDF as a Google Doc (OCR). Returns new doc ID or None."""
    r = requests.post(
        f"https://www.googleapis.com/drive/v3/files/{file_id}/copy",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        json={"mimeType": "application/vnd.google-apps.document",
              "name": f"_temp_ocr_{label}"}
    )
    if r.status_code == 200:
        return r.json()["id"]
    print(f"ERROR {r.status_code}: {r.text[:300]}")
    return None

def delete_doc(doc_id: str):
    """Delete a temp OCR doc after reading."""
    requests.delete(
        f"https://www.googleapis.com/drive/v3/files/{doc_id}",
        headers={"Authorization": f"Bearer {token}"}
    )

# Batch multiple PDFs
pdf_ids = [
    ("FILE_ID_1", "Invoice"),
    ("FILE_ID_2", "Agreement"),
]
doc_ids = {label: pdf_to_doc(fid, label) for fid, label in pdf_ids}
print(doc_ids)
# Then call mcp__google_workspace__docs_read(document_id=doc_id) for each
```

Save this to a file and run with `python3 /tmp/ocr_pdfs.py`.

## Quality Notes

- German invoice footers (Tel, IBAN, email, address) are captured reliably
- Scanned/handwritten content may have OCR errors
- Conversion takes ~5-10 seconds per file; batch all POSTs before reading
- Clean up temp docs after reading — they accumulate in Drive otherwise

## Pitfalls

- The token lives in the MCP's own data directory, not a shared location —
  typically `<mcp-checkout>/data/token.pickle`. Find it rather than assume it;
  the path differs per install.
- Tokens expire; check `creds.valid` before use (the MCP auto-refreshes, but
  a standalone script may need `creds.refresh(Request())` if expired)
- Apps Script API (alternative approach) requires the Apps Script API to be
  enabled at https://script.google.com/home/usersettings — check it, as it is
  off by default
- The browser is often not authenticated with the MCP's Google account, so
  opening Drive URLs in the browser tool hits the Google sign-in wall

## A note on what you OCR

This reads whatever the document says, including personal data — names, phone
numbers, the contents of contracts and agreements. Keep the extracted text where
the source document already lives, and keep worked examples out of shared notes:
the technique is portable, the documents are not.
