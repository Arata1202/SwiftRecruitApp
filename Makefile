.DEFAULT_GOAL := help

NPX ?= npx
ARGS ?= --help
ENV_FILE ?= supabase/.env.apple
FUNCTION ?= delete-account

# Quote single values without interpreting shell metacharacters.
quote = '$(subst ','"'"',$(1))'

.PHONY: help supabase supabase-start supabase-stop supabase-status supabase-login \
	supabase-link supabase-db-reset supabase-db-push-dry-run supabase-db-push \
	supabase-migration-new supabase-secrets-set supabase-functions-deploy

help:
	@printf '%s\n' \
	  'Supabase commands (via npx supabase):' \
	  '  make supabase-start / supabase-stop / supabase-status' \
	  '  make supabase-login' \
	  '  make supabase-link PROJECT_REF=your-project-ref' \
	  '  make supabase-db-reset                   Reset LOCAL DB (data loss)' \
	  '  make supabase-db-push-dry-run             Preview linked REMOTE DB changes' \
	  '  make supabase-db-push                     Apply to linked REMOTE DB' \
	  '  make supabase-migration-new NAME=add_example' \
	  '  make supabase-secrets-set [ENV_FILE=supabase/.env.apple]  Update REMOTE secrets' \
	  '  make supabase-functions-deploy [FUNCTION=delete-account] Deploy REMOTE function' \
	  '  make supabase ARGS="--help"               Pass arbitrary CLI arguments'

supabase:
	$(NPX) supabase $(ARGS)

supabase-start:
	$(NPX) supabase start

supabase-stop:
	$(NPX) supabase stop

supabase-status:
	$(NPX) supabase status

supabase-login:
	$(NPX) supabase login

supabase-link:
	@test -n $(call quote,$(strip $(PROJECT_REF))) || { echo 'PROJECT_REF is required: make supabase-link PROJECT_REF=your-project-ref' >&2; exit 1; }
	$(NPX) supabase link --project-ref $(call quote,$(PROJECT_REF))

supabase-db-reset:
	$(NPX) supabase db reset --local

supabase-db-push-dry-run:
	$(NPX) supabase db push --linked --dry-run

supabase-db-push:
	$(NPX) supabase db push --linked

supabase-migration-new:
	@test -n $(call quote,$(strip $(NAME))) || { echo 'NAME is required: make supabase-migration-new NAME=add_example' >&2; exit 1; }
	$(NPX) supabase migration new $(call quote,$(NAME))

supabase-secrets-set:
	@test -n $(call quote,$(strip $(ENV_FILE))) || { echo 'ENV_FILE must not be empty' >&2; exit 1; }
	$(NPX) supabase secrets set --env-file $(call quote,$(ENV_FILE))

supabase-functions-deploy:
	@test -n $(call quote,$(strip $(FUNCTION))) || { echo 'FUNCTION must not be empty' >&2; exit 1; }
	$(NPX) supabase functions deploy $(call quote,$(FUNCTION))
