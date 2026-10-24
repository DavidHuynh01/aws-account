# aws-account

The shared foundation of my AWS account, as Terraform. Each app deploys
itself with AWS SAM from its own repo; this repo owns what they share:

- **Keyless CI**: the GitHub OIDC provider, and a deploy role per app
  ([SkyblockZordle](https://github.com/DavidHuynh01/SkyblockZordle),
  [skyblock-market](https://github.com/DavidHuynh01/skyblock-market)), each
  pinned to one repo's `main` branch.
- **Permissions boundaries** that cap every role those deploys can create, so a
  compromised pipeline can't grant itself more than its app needs.
- **Cost guardrail**: a monthly budget with an email alert.
- **HTTPS**: the certificate for [skyblockzordle.com](https://skyblockzordle.com).
- **Its own state**: an encrypted, versioned S3 bucket with state locking.

Everything here existed before this repo did. It was imported, not
recreated, so no app noticed the move.

## How changes happen

CI runs `terraform plan` on every pull request and weekly, using a role that
can only read. Policy tests (`tests/`) check the planned IAM and fail if a
change would let a deploy role escape its boundary, manage itself, or trust
another repository. A person reviews the plan and runs `apply`.
