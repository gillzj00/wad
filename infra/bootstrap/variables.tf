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
