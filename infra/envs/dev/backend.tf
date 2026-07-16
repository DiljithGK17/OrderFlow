terraform {
  backend "s3" {
    bucket         = "orderflow-tfstate-1784186425"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "orderflow-tf-lock"
    encrypt        = true
  }
}
