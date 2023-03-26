variable "region" {
  description = "The region of your deployment"
  type        = string
  default     = "eu-central-1"
}

variable "deploy_key" {
  description = "The name of the key that will be used for deploy"
  type        = string
  default     = "~/.ssh/ghdeploykey"
}

variable "open_ports" {
  description = "The ports that will be open in your instance."

  type    = list(number)
  default = [22, 80]
}
