# CI access for SkyblockZordle (github.com/DavidHuynh01/SkyblockZordle). Its
# own SAM template builds the app; these are the account-level pieces that let
# GitHub Actions deploy it, and cap what that deploy can create.

locals {
  zordle      = "skyblockzordle"
  zordle_ssm  = "/skyblockzordle"
  zordle_arns = "${local.region}:${local.account_id}"
}

# Ceiling for every role the deploy role creates or edits. A role's effective
# permissions are the intersection of its policies and this boundary, so even
# if CI attached AdministratorAccess to a role it creates, that role could
# still only do what the API Lambda needs. The deploy role can't edit this.
resource "aws_iam_policy" "zordle_boundary" {
  name        = "${local.zordle}-lambda-boundary"
  description = "Permissions boundary for roles created by the CI deploy role"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:BatchGetItem",
          "dynamodb:BatchWriteItem",
          "dynamodb:Query",
          "dynamodb:Scan",
          "dynamodb:ConditionCheckItem",
          "dynamodb:DescribeTable",
        ]
        Resource = [
          "arn:aws:dynamodb:${local.zordle_arns}:table/${local.zordle}*",
          "arn:aws:dynamodb:${local.zordle_arns}:table/${local.zordle}*/index/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${local.zordle_arns}:parameter${local.zordle_ssm}/*"
      },
      # SecureString parameters are decrypted through SSM only.
      {
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = "*"
        Condition = { StringEquals = { "kms:ViaService" = "ssm.${local.region}.amazonaws.com" } }
      },
      {
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "arn:aws:logs:${local.zordle_arns}:log-group:/aws/lambda/${local.zordle}*",
          "arn:aws:logs:${local.zordle_arns}:log-group:/aws/lambda/${local.zordle}*:*",
        ]
      },
    ]
  })
}

resource "aws_iam_role" "zordle_deploy" {
  # Must NOT start with "skyblockzordle": the policy below manages roles named
  # skyblockzordle*, and a name inside that pattern could grant itself anything.
  name                 = "github-deploy-${local.zordle}"
  description          = "Assumed by GitHub Actions to deploy the application stack"
  max_session_duration = 3600
  assume_role_policy   = local.deploy_trust["SkyblockZordle"]
}

resource "aws_iam_role_policy" "zordle_deploy" {
  name = "deploy"
  role = aws_iam_role.zordle_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # CloudFormation drives the deployment of this stack only.
      {
        Effect = "Allow"
        Action = [
          "cloudformation:CreateChangeSet",
          "cloudformation:DescribeChangeSet",
          "cloudformation:ExecuteChangeSet",
          "cloudformation:DeleteChangeSet",
          "cloudformation:DescribeStacks",
          "cloudformation:DescribeStackEvents",
          "cloudformation:DescribeStackResource",
          "cloudformation:DescribeStackResources",
          "cloudformation:GetTemplateSummary",
          "cloudformation:ListStackResources",
        ]
        Resource = [
          "arn:aws:cloudformation:${local.zordle_arns}:stack/${local.zordle}/*",
          "arn:aws:cloudformation:${local.zordle_arns}:stack/aws-sam-cli-managed-default/*",
        ]
      },
      # Expanding the SAM macro into plain CloudFormation.
      {
        Effect   = "Allow"
        Action   = "cloudformation:CreateChangeSet"
        Resource = "arn:aws:cloudformation:${local.region}:aws:transform/Serverless-2016-10-31"
      },
      # SAM's managed bucket for build artifacts, plus the site bucket the
      # built frontend is published to.
      {
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:PutBucketPolicy",
          "s3:PutBucketTagging",
          "s3:PutBucketVersioning",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:GetBucketPolicy",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = [
          "arn:aws:s3:::aws-sam-cli-managed-default*",
          "arn:aws:s3:::aws-sam-cli-managed-default*/*",
          "arn:aws:s3:::${local.zordle}*",
          "arn:aws:s3:::${local.zordle}*/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = "arn:aws:lambda:${local.zordle_arns}:function:${local.zordle}*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:CreateTable",
          "dynamodb:DeleteTable",
          "dynamodb:DescribeTable",
          "dynamodb:DescribeTimeToLive",
          "dynamodb:UpdateTable",
          "dynamodb:UpdateTimeToLive",
          "dynamodb:TagResource",
          "dynamodb:ListTagsOfResource",
        ]
        Resource = "arn:aws:dynamodb:${local.zordle_arns}:table/${local.zordle}*"
      },
      # The Lambda execution role is created and attached by the stack.
      # Anything that can add permissions to a role is allowed only when that
      # role carries the boundary, so CI can't mint a role more powerful than
      # the API Lambda needs.
      {
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:AttachRolePolicy",
          "iam:PutRolePolicy",
          "iam:PutRolePermissionsBoundary",
        ]
        Resource  = "arn:aws:iam::${local.account_id}:role/${local.zordle}*"
        Condition = { StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.zordle_boundary.arn } }
      },
      # Read, tag and remove-only actions; none of these can widen a role.
      {
        Effect = "Allow"
        Action = [
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
          "iam:DetachRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${local.zordle}*"
      },
      {
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = "arn:aws:iam::${local.account_id}:role/${local.zordle}*"
        Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
      },
      # CloudFront has no resource-level permissions for these calls.
      {
        Effect = "Allow"
        Action = [
          "cloudfront:CreateDistribution",
          "cloudfront:UpdateDistribution",
          "cloudfront:GetDistribution",
          "cloudfront:GetDistributionConfig",
          "cloudfront:TagResource",
          "cloudfront:CreateOriginAccessControl",
          "cloudfront:UpdateOriginAccessControl",
          "cloudfront:GetOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl",
          "cloudfront:CreateInvalidation",
        ]
        Resource = "*"
      },
      # Read-only: lets CloudFront's update check the custom domain's
      # certificate. Can't create, change or export certificates.
      {
        Effect   = "Allow"
        Action   = ["acm:DescribeCertificate", "acm:ListCertificates"]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy",
          "logs:TagResource",
        ]
        Resource = "arn:aws:logs:${local.zordle_arns}:log-group:/aws/lambda/${local.zordle}*"
      },
    ]
  })
}
