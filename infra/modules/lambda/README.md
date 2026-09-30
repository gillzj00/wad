# lambda

One Lambda function from a prebuilt handler bundle: zips `backend/dist/<handler>/index.mjs`, creates the execution role (logging plus the function's own inline policy), a log group with short retention, and the function (Node 22, arm64, `index.handler`).

Inputs: `name`, `source_file`, `environment`, `policy_json`, `memory_size`, `timeout`, `log_retention_days`.
Outputs: `function_name`, `arn`, `invoke_arn`, `role_name`.

The bundle must exist before `plan`; CI runs `npm ci && npm run build` in `backend/` first (see `.github/workflows/terraform.yml`). The zip is written to `build/` under the environment directory, which is gitignored.
