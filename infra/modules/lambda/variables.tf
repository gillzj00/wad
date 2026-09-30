variable "name" {
  description = "Function name; also the role and log group name. Must start with the project prefix so the CI role may manage the IAM role."
  type        = string
}

variable "source_file" {
  description = "Path to the built handler bundle (backend/dist/<handler>/index.mjs)."
  type        = string
}

variable "environment" {
  description = "Environment variables for the function."
  type        = map(string)
  default     = {}
}

variable "policy_json" {
  description = "Inline IAM policy (JSON) granting the function what it needs beyond logging."
  type        = string
}

variable "memory_size" {
  description = "Memory in MB."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Timeout in seconds."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "CloudWatch log retention."
  type        = number
  default     = 14
}
