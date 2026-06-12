# Hypertube, Backend (Rails 8 API)

Rails 8 API-only backend.  
Runs entirely inside a Podman container, no local Ruby installation required.

---

## Requirements

- Podman + podman-compose (aliased as `docker` / `docker-compose`)
- No local Ruby, Bundler or Rails

---

## Environment Variables

Copy and fill in `api/.env.example` → `api/.env.local`:

| Variable                       | Description                                         |
|--------------------------------|-----------------------------------------------------|
| `DATABASE_HOST`                | PostgreSQL host (use `db` inside compose)           |
| `DATABASE_PORT`                | PostgreSQL port (default `5432`)                    |
| `DATABASE_NAME`                | Database name                                       |
| `DATABASE_USERNAME`            | Database user                                       |
| `DATABASE_PASSWORD`            | Database password                                   |
| `RAILS_ENV`                    | `development` / `production`                        |
| `SECRET_KEY_BASE`              | Rails secret key                                    |
| `JWT_SECRET_KEY`               | Secret for devise-jwt                               |
| `OMNIAUTH_42_CLIENT_ID`        | 42 Intra OAuth app client ID                        |
| `OMNIAUTH_42_CLIENT_SECRET`    | 42 Intra OAuth app client secret                   |
| `OMNIAUTH_42_REDIRECT_URI`     | Callback URI registered with 42                     |
| `OMNIAUTH_GOOGLE_CLIENT_ID`    | Google OAuth2 client ID                             |
| `OMNIAUTH_GOOGLE_CLIENT_SECRET`| Google OAuth2 client secret                        |
| `FRONTEND_URL`                 | Allowed CORS origin (e.g. `http://localhost:5173`)  |
| `API_URL`                      | Base URL shown in Swagger (e.g. `http://localhost:3000`) |
| `REDIS_URL`                    | Redis connection string                             |
| `OMDB_API_KEY`                 | OMDb API key                                        |
| `TMDB_API_KEY`                 | TMDB API key                                        |

---

## First-Time Setup

Run these from the **repo root**:

```bash
make init     # build image + run init.sh (rails new + gem install + generators)
make up       # start db + redis + api
make migrate  # bundle exec rails db:migrate
```

---

## Daily Development

```bash
make up         # start services
make down       # stop services
make bash       # shell inside backend container
make console    # rails console
make routes     # print routes
make migrate    # run new migrations
make rollback   # roll back last migration
make seed       # rails db:seed
make db-reset   # drop → create → migrate → seed
```

---

## Running Tests

```bash
make test       # rspec (no coverage)
make coverage   # rspec + SimpleCov → coverage/index.html
```

Set `COVERAGE=true` to enable SimpleCov on any run:

```bash
docker compose run --rm backend sh -c "COVERAGE=true bundle exec rspec"
```

---

## Generating API Docs

The OpenAPI spec is generated from request specs (rswag):

```bash
# from repo root
make bash
bundle exec rails rswag:specs:swaggerize
```

This writes `swagger/v1/swagger.yaml`.  
Swagger UI is served at **http://localhost:3000/api-docs** when the server is running.

To generate a standalone static HTML page:

```bash
bunx @redocly/cli build-docs swagger/v1/swagger.yaml -o docs/api.html
```

---

## Authentication Flow

### Password grant (email/password)

```
POST /oauth/token
Content-Type: application/json

{
  "grant_type": "password",
  "username": "user@example.com",
  "password": "secret"
}
```

Returns `{ "access_token": "...", "token_type": "Bearer", "expires_in": 7200 }`.

Use the token on every protected request:

```
Authorization: Bearer <access_token>
```

### OmniAuth (42 Intra / Google)

```
GET /users/auth/fortytwo
GET /users/auth/google_oauth2
```

Callback creates or finds the user via `User.from_omniauth` and exchanges for a Doorkeeper token.

---

## Code Structure

```
api/
├── app/
│   ├── controllers/
│   │   └── api/v1/          # versioned API controllers
│   ├── models/              # User, Movie, Comment, WatchHistory
│   └── jobs/                # Sidekiq background jobs
├── config/
│   ├── initializers/
│   │   ├── doorkeeper.rb    # OAuth2 config
│   │   └── devise.rb
│   └── routes.rb
├── db/
│   └── migrate/
├── spec/
│   ├── factories/           # FactoryBot factories
│   ├── models/              # model specs
│   ├── requests/api/v1/     # rswag request specs (also generate docs)
│   └── swagger_helper.rb    # OpenAPI root config
├── swagger/v1/swagger.yaml  # swagger config
├── Dockerfile.dev           # dev container image
├── Dockerfile.production    # production multi-stage image
└── entrypoint.sh
```

---

## Adding a Generator

```bash
make generate g="model Subtitle movie:references content:text language:string"
make migrate
```

---

## Useful One-Liners

```bash
# open psql inside the db container
docker compose exec db psql -U $DATABASE_USERNAME -d $DATABASE_NAME

# tail Rails logs
docker compose logs -f backend

# re-install gems after Gemfile change
docker compose run --rm backend bundle install
```
