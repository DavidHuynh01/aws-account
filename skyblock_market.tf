# CI access for skyblock-market (github.com/DavidHuynh01/skyblock-market), the
# auction data collector. Its SAM template builds the app; these let GitHub
# Actions deploy it, and cap what that deploy can create.

locals {
  market      = "skyblock-market"
  market_arns = "${local.region}:${local.account_id}"
}

# The most any role the collector stack creates can ever do: add sales under
# raw/, write its own logs, and let the scheduler start the function. The
# deploy role can't create or widen a role without this attached, and has no
# permission to edit it.
resource "aws_iam_policy" "market_boundary" {
  name        = "${local.market}-role-boundary"
  description = "Permissions boundary for every role in the skyblock-market stack"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SaveSales"
        Effect   = "Allow"
        Action   = "s3:PutObject"
        Resource = "arn:aws:s3:::${local.market}-*/raw/*"
      },
      {
        Sid      = "WriteOwnLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${local.market_arns}:log-group:/aws/lambda/${local.market}-*"
      },
      {
        Sid      = "StartTheCollector"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = "arn:aws:lambda:${local.market_arns}:function:${local.market}-*"
      },
    ]
  })
}

resource "aws_iam_role" "market_deploy" {
  # Deliberately outside the "skyblock-market-*" pattern its permissions
  # cover, so the role can't change its own permissions.
  name                 = "github-deploy-${local.market}"
  max_session_duration = 3600
  assume_role_policy   = local.deploy_trust["skyblock-market"]
}

resource "aws_iam_role_policy" "market_deploy" {
  name = "deploy"
  role = aws_iam_role.market_deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ThisStack"
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
          "cloudformation:GetTemplate",
          "cloudformation:GetTemplateSummary",
          "cloudformation:ListStackResources",
        ]
        Resource = [
          "arn:aws:cloudformation:${local.market_arns}:stack/${local.market}/*",
          "arn:aws:cloudformation:${local.market_arns}:stack/aws-sam-cli-managed-default/*",
        ]
      },
      {
        Sid      = "SamTransform"
        Effect   = "Allow"
        Action   = "cloudformation:CreateChangeSet"
        Resource = "arn:aws:cloudformation:${local.region}:aws:transform/Serverless-2016-10-31"
      },
      # Finding SAM's artifact bucket for the code upload. No bucket settings
      # at all: changing a bucket's policy or public access goes through an
      # admin deploy instead.
      {
        Sid      = "ArtifactBucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"]
        Resource = "arn:aws:s3:::aws-sam-cli-managed-default*"
      },
      # The code upload only. The deploy role can't read or write the
      # collected sales.
      {
        Sid      = "SamArtifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::aws-sam-cli-managed-default*/*"
      },
      {
        Sid      = "Function"
        Effect   = "Allow"
        Action   = "lambda:*"
        Resource = "arn:aws:lambda:${local.market_arns}:function:${local.market}-*"
      },
      # Roles can only be created or given permissions with the boundary
      # attached, so no role this pipeline makes can ever exceed it. Without
      # this, it could create a role, attach AdministratorAccess and run a
      # function as that role: full control of the account.
      {
        Sid    = "StackRolesInsideBoundary"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:PutRolePolicy",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:PutRolePermissionsBoundary",
        ]
        Resource  = "arn:aws:iam::${local.account_id}:role/${local.market}-*"
        Condition = { StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.market_boundary.arn } }
      },
      {
        Sid    = "StackRolesHousekeeping"
        Effect = "Allow"
        Action = [
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:UpdateAssumeRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies",
        ]
        Resource = "arn:aws:iam::${local.account_id}:role/${local.market}-*"
      },
      {
        Sid      = "PassStackRolesToTheirServices"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${local.account_id}:role/${local.market}-*"
        Condition = {
          StringEquals = { "iam:PassedToService" = ["lambda.amazonaws.com", "scheduler.amazonaws.com"] }
        }
      },
      {
        Sid    = "Schedule"
        Effect = "Allow"
        Action = [
          "scheduler:CreateSchedule",
          "scheduler:UpdateSchedule",
          "scheduler:DeleteSchedule",
          "scheduler:GetSchedule",
          "scheduler:TagResource",
          "scheduler:UntagResource",
          "scheduler:ListTagsForResource",
        ]
        Resource = "arn:aws:scheduler:${local.market_arns}:schedule/default/${local.market}-*"
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:DeleteLogGroup",
          "logs:PutRetentionPolicy",
          "logs:DeleteRetentionPolicy",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:TagLogGroup",
          "logs:ListTagsForResource",
        ]
        Resource = "arn:aws:logs:${local.market_arns}:log-group:/aws/lambda/${local.market}-*"
      },
      {
        Sid    = "AlertTopic"
        Effect = "Allow"
        Action = [
          "sns:CreateTopic",
          "sns:DeleteTopic",
          "sns:GetTopicAttributes",
          "sns:SetTopicAttributes",
          "sns:Subscribe",
          "sns:Unsubscribe",
          "sns:GetSubscriptionAttributes",
          "sns:ListSubscriptionsByTopic",
          "sns:TagResource",
          "sns:UntagResource",
          "sns:ListTagsForResource",
        ]
        Resource = "arn:aws:sns:${local.market_arns}:${local.market}-*"
      },
      {
        Sid    = "Alarms"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricAlarm",
          "cloudwatch:DeleteAlarms",
          "cloudwatch:TagResource",
          "cloudwatch:UntagResource",
          "cloudwatch:ListTagsForResource",
        ]
        Resource = "arn:aws:cloudwatch:${local.market_arns}:alarm:${local.market}-*"
      },
      # These describe calls don't support resource-level permissions.
      {
        Sid      = "Describe"
        Effect   = "Allow"
        Action   = ["cloudwatch:DescribeAlarms", "logs:DescribeLogGroups"]
        Resource = "*"
      },
    ]
  })
}
