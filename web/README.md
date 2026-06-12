# Hypertube, Frontend (React + Vite)

React 19 SPA built with Vite and Bun.  
Communicates with the Rails 8 API via Axios with automatic Bearer token injection.

---

## Requirements

- [Bun](https://bun.sh/) 1.3+

---

## Environment Variables

Copy and fill in `web/.env.example` → `web/.env.local`:

| Variable          | Description                                          |
|-------------------|------------------------------------------------------|
| `VITE_API_URL`    | Backend base URL (e.g. `http://localhost:3000`)      |

> All frontend env vars must be prefixed with `VITE_` to be exposed in the browser bundle.

---

## Setup

```bash
cd web
bun install
```

---

## Development

```bash
bun dev         # start dev server → http://localhost:5173
```

The Vite dev server proxies nothing by default, the Axios client reads `VITE_API_URL` directly.

---

## Build

```bash
bun run build   # production build → dist/
bun run preview # preview the production build locally
```

---

## Linting

```bash
bun run lint    # ESLint
```

---

## Axios Client

`src/api/client.js` exports a pre-configured Axios instance:

- **Base URL** → `VITE_API_URL`
- **Request interceptor** → attaches `Authorization: Bearer <token>` from `localStorage`
- **Response interceptor** → redirects to `/login` on 401

```js
import api from "./api/client";

const { data } = await api.get("/api/v1/movies");
```

---

## Project Structure

```
web/
├── src/
│   ├── api/
│   │   └── client.js        # Axios instance + interceptors
│   ├── components/          # Reusable UI components
│   ├── pages/               # Route-level page components
│   ├── App.jsx              # Root component + routing
│   └── main.jsx             # Entry point
├── public/
├── .env.example
├── .env.local               # (git-ignored)
├── index.html
├── vite.config.js
└── package.json
```

---

## Available Scripts

| Command          | Description                        |
|------------------|------------------------------------|
| `bun dev`        | Start development server (HMR)     |
| `bun run build`  | Production build to `dist/`        |
| `bun run preview`| Serve the production build locally |
| `bun run lint`   | Run ESLint                         |

---

## Notes

- The `dist/` directory is git-ignored; it is rebuilt on each deploy.
- `node_modules/` is git-ignored; run `bun install` after cloning.
- TypeScript is intentionally not used in this project.
