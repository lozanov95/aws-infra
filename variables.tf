variable "ami_id" {
  description = "Id of the AMI that will be used for the instance"
  type        = string
  default     = "ami-08868ffb88a12d582"
}

variable "region" {
  description = "The region of your deployment"
  type        = string
  default     = "eu-central-1"
}

variable "deploy_key" {
  description = "The name of the key that will be used for deploy"
  type        = string
  default     = "ghdeploykey"
}

variable "open_ports" {
  description = "The ports that will be open in your instance."

  type    = list(number)
  default = [80]
}

variable "ssh_open_ips" {
  description = "(Optional) The ips that will be able to ssh to the server."

  type    = list(string)
  default = ["84.238.195.45", "212.39.80.42"]
}
