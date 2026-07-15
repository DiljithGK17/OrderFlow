terraform {
  backend "s3" {
    bucket         = "orderflow-tfstate-12345"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "orderflow-tf-lock"
    encrypt        = true
  }
}
