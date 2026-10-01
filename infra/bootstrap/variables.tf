variable "aws_region" {
  description = "AWS region for the state backend and infrastructure."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name, used as a prefix for resource names."
  type        = string
  default     = "wad"
}

variable "github_owner" {
  description = "GitHub owner/org that owns the repository."
  type        = string
  default     = "gillzj00"
}

variable "github_repo" {
  description = "GitHub repository name."
  type        = string
  default     = "wad"
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID, used in immutable OIDC subject claims."
  type        = string
  default     = "5639243"
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID, used in immutable OIDC subject claims."
  type        = string
  default     = "1387929117"
}

variable "ci_environment" {
  description = "GitHub Environment the Terraform apply job runs in; its required-reviewer rule gates deploys."
  type        = string
  default     = "dev"
}
