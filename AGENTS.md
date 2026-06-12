# Repository Guidelines

## Project Structure & Module Organization
`docs/en/` contains the English documentation, organized by product area such as `kubeflow/`, `workbench/`, and `model_inference/`. Section landing pages usually live in `index.mdx`, with supporting content under folders like `overview/`, `how_to/`, `functions/`, and `trouble_shooting/`. Put downloadable files and images in `docs/public/` or the nearest section asset folder. Shared generated resources live in `docs/shared/` (`crds/`, `openapis/`, `roletemplates/`, `functionresources/`). Root config lives in `doom.config.yml`, `sites.yaml`, `eslint.config.js`, and `cspell.config.js`. CI definitions are under `.builds/`.

## Build, Test, and Development Commands
Use Yarn 4 for all local work:

- `yarn install`: install dependencies.
- `yarn dev`: start the Doom dev server with live reload.
- `yarn lint`: run repository lint checks before committing.
- `yarn build`: produce the static site in `dist/`.
- `yarn serve`: preview the built site locally.
- `yarn translate` / `yarn export`: run Doom translation or export workflows when needed.

## Coding Style & Naming Conventions
Follow `.editorconfig`: 2-space indentation, LF line endings, UTF-8, and a final newline. Prettier is the formatter; its current rules prefer single quotes and no semicolons. Keep MDX concise and use descriptive headings. Match the surrounding directory’s naming pattern; for new pages, prefer lowercase filenames and keep section entry files as `index.mdx`, `intro.mdx`, or `features.mdx` when they serve those roles.

## Testing Guidelines
There is no separate unit-test suite in this repository. Validation is content-focused: run `yarn lint` and `yarn build` for every change, then use `yarn serve` or `yarn dev` to verify rendering, navigation, links, code blocks, and asset paths. Treat a clean build as the minimum acceptance bar.

## Commit & Pull Request Guidelines
Recent history favors short, imperative commit subjects such as `Add trainerv2 llm fine tuning (#156)` or `Split component tables by architecture...`. Keep commits focused on one documentation change. For pull requests, include a concise summary, link the relevant issue or task, and note any generated or copied assets. Add screenshots only when navigation, theme behavior, or visual assets change. Ensure `yarn lint` passes before opening the PR.
