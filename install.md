# Instalación · Install

## Castellano

### Requisitos
- macOS 26.5 o posterior.
- Mac con Apple Silicon.

### Instalar
1. Ve a la pestaña **Releases** del repositorio y descarga el último `Óculo.zip`.
2. Descomprímelo y arrastra `Óculo.app` a tu carpeta **Aplicaciones**.
3. La primera vez: **clic derecho sobre la app ▸ Abrir** y confirma. Hay que hacerlo así porque la app no está firmada ni notarizada por Apple (no pago la cuota de desarrollador). No es malware; es código abierto que puedes revisar.

Si macOS sigue sin dejarte abrirla, en Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Óculo.app
```

### Primer uso
- Abre Óculo y pulsa **Abrir biblioteca…** en la barra lateral para apuntar a una carpeta de documentos. Óculo solo lee: nunca mueve, copia ni modifica nada.
- Puedes añadir varias bibliotecas. Cada una se navega y se busca por separado.
- Opcional: en **Ajustes** puedes elegir idioma, la bóveda de notas y la búsqueda afinada con un LLM local (ver `setup-local-llm-intelligent-search.md`).

---

## English

### Requirements
- macOS 26.5 or later.
- Apple Silicon Mac.

### Install
1. Open the repository's **Releases** tab and download the latest `Óculo.zip`.
2. Unzip it and drag `Óculo.app` into your **Applications** folder.
3. First launch: **right-click the app ▸ Open** and confirm. This step is needed because the app is not signed or notarized by Apple (I don't pay the developer fee). It is not malware; it is open source you can inspect.

If macOS still refuses to open it, in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Óculo.app
```

### First run
- Open Óculo and click **Open library…** in the sidebar to point at a folder of documents. Óculo only reads: it never moves, copies or modifies anything.
- You can add several libraries. Each is browsed and searched separately.
- Optional: in **Settings** you can pick the language, the notes vault, and refined search with a local LLM (see `setup-local-llm-intelligent-search.md`).
