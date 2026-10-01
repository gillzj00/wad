terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Bootstrap uses LOCAL state: it creates the very bucket that stores remote state.
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  state_bucket = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  # The repo uses GitHub's immutable OIDC subject claims, which embed the
  # owner and repo numeric IDs: repo:<owner>@<owner_id>/<repo>@<repo_id>:<context>
  repo_sub_prefix = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}"
  # Only these workflow contexts may assume the CI role (exact match, no
  # wildcards): the read-only plan on pull requests, the apply job (which runs
  # in the `dev` environment, so its subject is the environment, not the ref),
  # and any other job on main. Fork pull requests never get an OIDC token.
  ci_subjects = [
    "${local.repo_sub_prefix}:pull_request",
    "${local.repo_sub_prefix}:environment:${var.ci_environment}",
    "${local.repo_sub_prefix}:ref:refs/heads/main",
  ]
}

# ---------------------------------------------------------------------------
# Remote state backend: versioned, encrypted S3 bucket. State locking uses an
# S3 lock file (use_lockfile), so no DynamoDB lock table is needed.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# GitHub OIDC provider + CI role assumable only from this repository
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

data "aws_iam_policy_document" "ci_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = local.ci_subjects
    }
  }
}

resource "aws_iam_role" "ci" {
  name               = "${var.project}-ci"
  assume_role_policy = data.aws_iam_policy_document.ci_assume.json
}

# State access for CI.
data "aws_iam_policy_document" "ci_state" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }
}

resource "aws_iam_role_policy" "ci_state" {
  name   = "state-access"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_state.json
}

# App infra deploy permissions for CI.
# NOTE: intentionally broad to unblock early milestones; TIGHTEN before prod
# by scoping to the specific services/resources the stack actually manages.
data "aws_iam_policy_document" "ci_deploy" {
  statement {
    sid    = "AppServices"
    effect = "Allow"
    actions = [
      "dynamodb:*",
      "lambda:*",
      "apigateway:*",
      "cognito-idp:*",
      "logs:*",
      "events:*",
      "ssm:*",
      "cloudwatch:*",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "IamForServiceRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:PassRole",
      "iam:TagRole",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.project}-*"]
  }
}

resource "aws_iam_role_policy" "ci_deploy" {
  name   = "deploy"
  role   = aws_iam_role.ci.id
  policy = data.aws_iam_policy_document.ci_deploy.json
}
