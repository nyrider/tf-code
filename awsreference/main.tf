provider "aws" {
  region                  = "us-west-2"
  shared_credentials_file = "/.../.aws/credentials"
  profile                 = "default"
}


module "tf-ref-vpc" {
  source = "github.com/azavea/terraform-aws-vpc"
  name = "tf-ref-vpc"
  key_name = "tf-dev-account"
  bastion_ami = "ami-e689729e"
  region = "us-west-2"
  availability_zones = ["us-west-2b","us-west-2c" ]
}
