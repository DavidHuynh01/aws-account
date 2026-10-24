# What this repo's own CI may do: read, never change. CI runs `terraform plan`
# on every pull request and weekly to catch drift; only a person applies.
# Even a malicious pull request can't use this role to alter the account.

locals {
  this_repo = "aws-account"
}

resource "aws_iam_role" "plan" {
  name                 = "github-plan-${local.this_repo}"
  description          = "Assumed by GitHub Actions in aws-account to run terraform plan (read-only)"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      # This repo only, but any branch or pull request: planning is harmless.
      Condition = {
        StringEquals = {
          "${local.oidc}:aud"        = "sts.amazonaws.com"
          "${local.oidc}:repository" = "${local.github_owner}/${local.this_repo}"
        }
        StringLike = {
          "${local.oidc}:sub" = [
            "repo:${local.github_owner}/${local.this_repo}:*",
            "repo:${local.github_owner}@*/${local.this_repo}@*:*",
          ]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "plan" {
  name = "plan"
  role = aws_iam_role.plan.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Refreshing what this repo manages. Read calls only.
      {
        Sid    = "ReadManagedResources"
        Effect = "Allow"
        Action = [
          "iam:GetOpenIDConnectProvider",
          "iam:GetRole",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
          "iam:ListRoleTags",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:ListPolicyTags",
          "acm:DescribeCertificate",
          "acm:ListTagsForCertificate",
          "budgets:ViewBudget",
          "budgets:ListTagsForResource",
        ]
        Resource = "*"
      },
      # The state bucket's own settings, which this repo also manages.
      {
        Sid      = "ReadStateBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucket*", "s3:GetEncryptionConfiguration", "s3:GetLifecycleConfiguration", "s3:GetAccelerateConfiguration", "s3:GetReplicationConfiguration"]
        Resource = aws_s3_bucket.state.arn
      },
      {
        Sid      = "ReadState"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.state.arn}/*"
      },
      # Plan takes the lock too, so it never reads state mid-apply. The lock
      # file is the only thing this role can write.
      {
        Sid      = "StateLock"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.state.arn}/*.tflock"
      },
    ]
  })
}

output "plan_role_arn" {
  description = "Store as the AWS_PLAN_ROLE_ARN secret in this repo"
  value       = aws_iam_role.plan.arn
  sensitive   = true
}
