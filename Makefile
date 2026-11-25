.PHONY: setup services dev api web test test-api test-web seed up down pgadmin

## First-time setup: start Postgres/Redis, install deps, create + seed DB
setup: services
	cd api && bundle install && bin/rails db:prepare db:seed
	cd web && pnpm install

## Start only infrastructure (Postgres + Redis) in Docker
services:
	docker compose up -d --wait db redis

## Run API + web natively (requires `make services`)
dev: services
	@trap 'kill 0' INT; \
	(cd api && bin/rails server -p 3000) & \
	(cd web && pnpm dev) & \
	wait

api:
	cd api && bin/rails server -p 3000

web:
	cd web && pnpm dev

seed:
	cd api && bin/rails db:seed:replant

test: test-api test-web

test-api:
	cd api && bundle exec rspec

test-web:
	cd web && pnpm test

## Run the whole stack in Docker
up:
	docker compose up --build

## Optional database GUI on http://localhost:5050 (see README)
pgadmin:
	docker compose --profile tools up -d --wait pgadmin
	@echo "pgAdmin: http://localhost:5050  (login dev@example.com / pgadmin; Postgres password: postgres)"

down:
	docker compose --profile tools down
