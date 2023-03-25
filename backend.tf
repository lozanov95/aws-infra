terraform {
  backend "s3" {
    bucket  = "s3-vt-tfstate"
    key     = "tfstate/aws-infra"
    region  = "eu-central-1"
    encrypt = true
  }
}
