# Keyless CI. AWS trusts tokens from GitHub's OIDC endpoint, so no AWS access
# keys live in any repository or GitHub secret. An account can have only one
# provider per URL, which is why it lives here and not in either app's repo.
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]

  lifecycle {
    # Every CI pipeline in the account signs in through this.
    prevent_destroy = true
  }
}

locals {
  oidc = "token.actions.githubusercontent.com"

  # Trust for an app's deploy role: one repo, one branch.
  #
  # The real pins are `repository` and `ref`, matched exactly. `sub` is matched
  # loosely because GitHub embeds immutable numeric ids in it
  # (repo:owner@123/name@456:ref:refs/heads/main), and a job with a deployment
  # environment gets ":environment:<name>" instead of ":ref:<branch>". IAM
  # still refuses a trust policy that doesn't constrain `sub` at all.
  deploy_trust = {
    for repo in ["SkyblockZordle", "skyblock-market"] : repo => jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Effect    = "Allow"
        Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc}:aud"        = "sts.amazonaws.com"
            "${local.oidc}:repository" = "${local.github_owner}/${repo}"
            "${local.oidc}:ref"        = "refs/heads/main"
          }
          StringLike = {
            "${local.oidc}:sub" = [
              "repo:${local.github_owner}/${repo}:ref:refs/heads/main",
              "repo:${local.github_owner}@*/${repo}@*:ref:refs/heads/main",
              "repo:${local.github_owner}/${repo}:environment:production",
              "repo:${local.github_owner}@*/${repo}@*:environment:production",
            ]
          }
        }
      }]
    })
  }
}
