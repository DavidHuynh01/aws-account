# Account-wide pieces that don't belong to either app.

variable "alert_email" {
  description = "Where the budget alert goes. Kept out of the repo: set TF_VAR_alert_email locally, a secret in CI."
  type        = string
  sensitive   = true
}

# A hard-to-miss warning before a surprise bill: an email once actual spend
# for the month passes $2.
#
# Credits are left out of the total on purpose. The account is on AWS's free
# plan, and with credits counted the bill nets to $0, so the alert could never
# fire however much was being used until the credits ran out.
resource "aws_budgets_budget" "monthly" {
  name              = "My Zero-Spend Budget"
  budget_type       = "COST"
  limit_amount      = "2.0"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-10-01_00:00"
  billing_view_arn  = "arn:aws:billing::${local.account_id}:billingview/primary"

  cost_types {
    include_credit = false
  }

  notification {
    notification_type          = "ACTUAL"
    comparison_operator        = "GREATER_THAN"
    threshold                  = 2
    threshold_type             = "ABSOLUTE_VALUE"
    subscriber_email_addresses = [var.alert_email]
  }
}

# HTTPS for skyblockzordle.com. CloudFront requires it in us-east-1. It is
# validated by DNS, so ACM renews it by itself for as long as the validation
# records stay in place.
resource "aws_acm_certificate" "site" {
  domain_name               = "skyblockzordle.com"
  subject_alternative_names = ["www.skyblockzordle.com"]
  validation_method         = "DNS"
  key_algorithm             = "RSA_2048"

  lifecycle {
    # The live site serves this certificate; replacing it would take HTTPS down.
    prevent_destroy = true
  }
}
