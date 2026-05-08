# Model Sync API Routes

## Owner

- Repository: `ltbase-private-deployment`
- Task type: deployment template / API Gateway route registration

## Plan

- Confirm `ltbase.api` already handles `GET` and `POST /api/ai/v1/notes/{note_id}/model_sync`.
- Add a failing route-spec test in the private deployment Pulumi code.
- Register both model sync routes with the existing `LTBase` authorizer.
- Run the targeted Go test package.
