"""Policy-as-code checks on the planned IAM, run in CI on every plan.

They read the JSON form of a Terraform plan (`terraform show -json`), which
holds every policy exactly as AWS will see it, account ID and all, and fail
if a change would let CI escalate its own access.
"""
import json
import os
from fnmatch import fnmatch

import pytest

PLAN = os.environ.get("PLAN_JSON", "plan.json")

# Actions that can give a role more power. Removing a policy can't push a role
# past its boundary, so detach/delete aren't on this list.
WIDENS_A_ROLE = {"iam:CreateRole", "iam:AttachRolePolicy", "iam:PutRolePolicy", "iam:PutRolePermissionsBoundary"}
# Ways out of a boundary: removing it, or editing the boundary policy itself.
ESCAPES = {
    "*", "iam:*",
    "iam:DeleteRolePermissionsBoundary",
    "iam:CreatePolicyVersion", "iam:SetDefaultPolicyVersion", "iam:DeletePolicyVersion",
}

APPS = {
    "zordle": {
        "role": "github-deploy-skyblockzordle",
        "repo": "DavidHuynh01/SkyblockZordle",
        "pass_to": {"lambda.amazonaws.com"},
    },
    "market": {
        "role": "github-deploy-skyblock-market",
        "repo": "DavidHuynh01/skyblock-market",
        "pass_to": {"lambda.amazonaws.com", "scheduler.amazonaws.com"},
    },
}


@pytest.fixture(scope="module")
def resources():
    with open(PLAN) as f:
        plan = json.load(f)
    return {r["address"]: r["values"] for r in plan["planned_values"]["root_module"]["resources"]}


def statements(doc):
    return json.loads(doc)["Statement"] if isinstance(doc, str) else doc["Statement"]


def as_list(x):
    return x if isinstance(x, list) else [x]


def deploy_policy(resources, app):
    return statements(resources[f"aws_iam_role_policy.{app}_deploy"]["policy"])


@pytest.mark.parametrize("app", APPS)
def test_roles_can_only_be_widened_inside_the_boundary(resources, app):
    boundary = resources[f"aws_iam_policy.{app}_boundary"]["arn"]
    for s in deploy_policy(resources, app):
        if WIDENS_A_ROLE & set(as_list(s["Action"])):
            cond = s.get("Condition", {}).get("StringEquals", {})
            assert cond.get("iam:PermissionsBoundary") == boundary, s


@pytest.mark.parametrize("app", APPS)
def test_nothing_can_escape_or_rewrite_a_boundary(resources, app):
    for s in deploy_policy(resources, app):
        assert not ESCAPES & set(as_list(s["Action"])), s


@pytest.mark.parametrize("app", APPS)
def test_roles_are_only_passed_to_the_apps_own_services(resources, app):
    for s in deploy_policy(resources, app):
        if "iam:PassRole" in as_list(s["Action"]):
            services = as_list(s["Condition"]["StringEquals"]["iam:PassedToService"])
            assert set(services) <= APPS[app]["pass_to"], s


@pytest.mark.parametrize("app", APPS)
def test_a_deploy_role_cant_manage_itself(resources, app):
    # Its name sits outside every role pattern it may manage.
    name = APPS[app]["role"]
    for s in deploy_policy(resources, app):
        for pattern in as_list(s["Resource"]):
            if ":role/" in pattern:
                own_arn = pattern.split(":role/")[0] + ":role/" + name
                assert not fnmatch(own_arn, pattern), pattern


@pytest.mark.parametrize("app", APPS)
def test_deploy_roles_trust_one_repo_on_main(resources, app):
    trust = statements(resources[f"aws_iam_role.{app}_deploy"]["assume_role_policy"])
    assert len(trust) == 1
    pins = trust[0]["Condition"]["StringEquals"]
    assert pins["token.actions.githubusercontent.com:repository"] == APPS[app]["repo"]
    assert pins["token.actions.githubusercontent.com:ref"] == "refs/heads/main"
    assert pins["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com"


def boundary_actions(resources, app):
    return {a for s in statements(resources[f"aws_iam_policy.{app}_boundary"]["policy"]) for a in as_list(s["Action"])}


def test_the_games_boundary_allows_only_what_its_lambda_needs(resources):
    allowed = {f"dynamodb:{a}" for a in ["GetItem", "PutItem", "UpdateItem", "DeleteItem", "BatchGetItem",
                                         "BatchWriteItem", "Query", "Scan", "ConditionCheckItem", "DescribeTable"]}
    allowed |= {"ssm:GetParameter", "ssm:GetParameters", "kms:Decrypt",
                "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"}
    assert boundary_actions(resources, "zordle") <= allowed


def test_the_collectors_boundary_allows_only_what_it_needs(resources):
    assert boundary_actions(resources, "market") == {
        "s3:PutObject", "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "lambda:InvokeFunction",
    }


def test_the_collectors_deploy_role_cant_change_any_buckets_settings(resources):
    for s in deploy_policy(resources, "market"):
        for a in as_list(s["Action"]):
            if a.startswith("s3:"):
                assert a in {"s3:GetObject", "s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"}, a


def test_ci_for_this_repo_can_only_read(resources):
    # The plan role's one write is the state lock file.
    for s in statements(resources["aws_iam_role_policy.plan"]["policy"]):
        for a in as_list(s["Action"]):
            verb = a.split(":")[1]
            if verb.startswith(("Get", "List", "Describe", "View")):
                continue
            assert a in {"s3:PutObject", "s3:DeleteObject"}, a
            assert all(r.endswith("/*.tflock") for r in as_list(s["Resource"])), s


def test_ci_for_this_repo_trusts_only_this_repo(resources):
    trust = statements(resources["aws_iam_role.plan"]["assume_role_policy"])
    pins = trust[0]["Condition"]["StringEquals"]
    assert pins["token.actions.githubusercontent.com:repository"] == "DavidHuynh01/aws-account"
