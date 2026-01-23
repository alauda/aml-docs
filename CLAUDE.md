# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a documentation site for Alauda AI built with **@alauda/doom**, an internal documentation framework based on Rspress. The site supports multiple documentation sites with different base paths and versions (configured in `sites.yaml`).

## Commands

- `yarn dev` - Start development server with hot reload (sidebar changes require restart)
- `yarn build` - Build production static files to `dist/` directory
- `yarn serve` - Preview production build locally
- `yarn lint` - Run ESLint (also runs automatically via git pre-commit hook)
- `yarn export` - Export documentation as PDF
- `yarn translate` - Run translation utilities

## Architecture

### Build System (@alauda/doom)

The project uses `@alauda/doom`, which wraps Rspress. Doom provides:
- Multi-site support via `sites.yaml` (each site has a name, base path, and version)
- API documentation generation from OpenAPI specs and Kubernetes CRDs
- Release notes integration with JIRA queries
- Custom linting rules for MDX content

### Directory Structure

- `docs/` - Documentation content
  - `en/` - English documentation (primary language)
    - `overview/`, `installation/`, `llm-compressor/`, etc. - Content sections
  - `public/` - Static assets (images, files for download)
  - `shared/` - Shared API definitions (CRDs, OpenAPI specs, role templates)
- `theme/` - Custom theme overrides
  - `layout/index.tsx` - Custom layout wrapping Rspress's default Layout
  - `utils/download.ts` - Logic to handle file download links for specific extensions
- `doom.config.yml` - Main configuration for sidebar, APIs, and release notes

### Theme Customization

The custom layout (`theme/layout/index.tsx`) extends Rspress's default layout with:
- `window.parent.postMessage()` - Communicates URL to parent window (for embedding)
- Custom `<a>` component - Adds `download` attribute to links with certain file extensions (.ipynb, .zip, .tgz, .tar.gz, .sh, .py, .sql)

### File Naming

- Use `.mdx` extension for documentation files with MDX syntax
- Use `.ipynb` for Jupyter notebooks (downloadable via custom link handler)
- Static assets in `docs/public/` are referenced with `/public/filename`

### Multi-Site Configuration

`sites.yaml` defines multiple documentation sites (acp, alauda-build-of-gitlab, servicemeshv1, hami, pgpu) each with its own base path and version. Some sites reference external GitHub repositories.
