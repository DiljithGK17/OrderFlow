terraform {
  backend "s3" {
    bucket         = "orderflow-tfstate-1784357686q"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "orderflow-tf-lock"
    encrypt        = true
  }
}
