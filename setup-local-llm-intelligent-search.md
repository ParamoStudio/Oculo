# Búsqueda inteligente con un LLM local · Local LLM intelligent search

## Castellano

### Dos marchas de búsqueda
- **Rápida (Enter).** Índice local (SQLite FTS5, ranking BM25F). Instantánea, sin IA, funciona siempre sobre toda tu biblioteca.
- **Afinada (Tab).** Usa un LLM local (vía Ollama) para encontrar conexiones que la rápida podría pasar por alto. Es lenta (segundos) pero la rápida siempre está disponible. **Todo local: nada sale de tu Mac.**

Si Ollama no está, la afinada avisa y la rápida sigue funcionando entera.

### La bóveda (digestión)
La búsqueda mejora mucho cuando tus documentos están "digeridos" en una **bóveda**: una carpeta de notas `.md` (una por documento) con metadata. Óculo empareja cada documento con su nota por **content_hash** (sobrevive a mover y renombrar) y usa esa metadata para buscar.

Óculo es solo **consumidor**: lee la bóveda, nunca la escribe. La digestión (convertir documentos en notas) es un paso aparte, propio de cada flujo. Una nota mínima tiene este aspecto:

```markdown
---
id: 9c1f4a2b
content_hash: sha256:4e91…
title: Experimentos en esmaltes cristalinos
aliases: [esmaltes cristalinos, crystalline glazes]
tags: [cerámica, esmaltes, cristalinos]
topics: [cono 6, ciclos de cocción, crecimiento de cristales]
summary: >
  Resumen breve del documento…
topic_pages:
  - {topic: cono 6, pages: [2, 4]}
related: [3e7d5c1a]
---
```

Campos que Óculo lee: `id`, `content_hash`, `title`, `aliases`, `tags`, `topics`, `summary`, `topic_pages`, `related`. Sin bóveda, todo se sigue buscando por nombre y ruta (degradación elegante).

### Instalar Ollama
1. Instala Ollama desde su web (`ollama.com`).
2. Descarga un modelo, por ejemplo:
   ```bash
   ollama pull qwen2.5:7b
   ```
3. Ollama queda escuchando en `http://127.0.0.1:11434` (loopback, local).

### Configurar en Óculo (Ajustes ▸ ⌘,)
- **Idioma:** inglés o castellano.
- **Bóveda:** elige la carpeta de notas `.md` (opcional).
- **Ollama:** nombre del modelo (`qwen2.5:7b` por defecto) y servidor (`http://127.0.0.1:11434`). Pulsa **Probar conexión** para verificar.
- **Atajos:** tecla de búsqueda (S) y de recientes (R).

### Cómo razona la afinada
Recibe tu consulta + la **metadata de la bóveda** (título, alias, tags, temas, resumen, `topic_pages`, grafo `related`). **Nunca el texto interior de los documentos.** Devuelve hasta 5 documentos rankeados, cada uno con una frase de *por qué* encaja y, si existen, las páginas relevantes. Las páginas se **verifican** contra el `topic_pages` real de la nota: si el modelo inventa una página, se descarta.

### Privacidad
Sin telemetría, sin cuentas, sin nube. El índice, los hashes y la configuración viven en tu Mac y son regenerables. El LLM corre en local.

---

## English

### Two search gears
- **Fast (Enter).** Local index (SQLite FTS5, BM25F ranking). Instant, no AI, always available across your whole library.
- **Refined (Tab).** Uses a local LLM (via Ollama) to surface connections fast search might miss. It's slower (seconds), but fast search is always there. **Fully local: nothing leaves your Mac.**

If Ollama isn't running, refined search says so and fast search keeps working fully.

### The vault (digestion)
Search gets much richer when your documents are "digested" into a **vault**: a folder of `.md` notes (one per document) with metadata. Óculo matches each document to its note by **content_hash** (survives moving and renaming) and uses that metadata to search.

Óculo is only a **consumer**: it reads the vault, never writes it. Digestion (turning documents into notes) is a separate step in your own workflow. A minimal note looks like:

```markdown
---
id: 9c1f4a2b
content_hash: sha256:4e91…
title: Experiments in crystalline glazes
aliases: [crystalline glazes]
tags: [ceramics, glazes, crystalline]
topics: [cone 6, firing cycles, crystal growth]
summary: >
  A short summary of the document…
topic_pages:
  - {topic: cone 6, pages: [2, 4]}
related: [3e7d5c1a]
---
```

Fields Óculo reads: `id`, `content_hash`, `title`, `aliases`, `tags`, `topics`, `summary`, `topic_pages`, `related`. Without a vault, everything is still searchable by name and path (graceful degradation).

### Install Ollama
1. Install Ollama from `ollama.com`.
2. Pull a model, for example:
   ```bash
   ollama pull qwen2.5:7b
   ```
3. Ollama listens on `http://127.0.0.1:11434` (loopback, local).

### Configure in Óculo (Settings ▸ ⌘,)
- **Language:** English or Spanish.
- **Vault:** choose the folder of `.md` notes (optional).
- **Ollama:** model name (`qwen2.5:7b` by default) and server (`http://127.0.0.1:11434`). Click **Test connection** to verify.
- **Shortcuts:** search key (S) and recents key (R).

### How refined search reasons
It receives your query + the **vault metadata** (title, aliases, tags, topics, summary, `topic_pages`, the `related` graph). **Never the document's inner text.** It returns up to 5 ranked documents, each with one line on *why* it fits and, if any, the relevant pages. Pages are **verified** against the note's real `topic_pages`: if the model invents a page, it's discarded.

### Privacy
No telemetry, no accounts, no cloud. The index, hashes and settings live on your Mac and are regenerable. The LLM runs locally.
