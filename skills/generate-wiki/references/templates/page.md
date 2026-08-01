---
title: "{{TITLE}}"
description: "{{DESCRIPTION}}"
generated_by: generate-wiki
generated_at: "{{DATE}}"
manual: false
sources:
  - {{SOURCE_PATH}}
---

# {{TITLE}}

## TL;DR

| Point | Detail | Source |
| --- | --- | --- |
| {{KEY_POINT}} | {{ONE_LINE}} | [`{{PATH}}:{{LINE}}`]({{BLOB_URL}}) |

## Why

{{WHY_THIS_EXISTS — first principles; cite sources}}

## How it fits

{{OPTIONAL_MERMAID_OR_SUMMARY}}

```mermaid
{{OPTIONAL_DIAGRAM — 0–2 per page; GitHub-native theme}}
```

<!-- sources: {{PATH:LINE}}, … -->

## Details

{{STRUCTURED_BODY — tables over prose for APIs, configs, modules}}

| Item | Responsibility | Source |
| --- | --- | --- |
| {{NAME}} | {{ROLE}} | [`{{PATH}}:{{LINE}}`]({{BLOB_URL}}) |

## Related

| Page | Relationship |
| --- | --- |
| [{{OTHER_TITLE}}](./{{OTHER_PATH}}) | {{WHY_RELATED}} |

## References

- {{DOC_LINK_OR_CODE_CITE}}
- Catalogue: [`catalogue.json`](./catalogue.json) leaf `{{ID}}`
