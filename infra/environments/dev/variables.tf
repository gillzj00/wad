variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix."
  type        = string
  default     = "wad"
}

variable "env" {
  description = "Environment name."
  type        = string
  default     = "dev"
}
