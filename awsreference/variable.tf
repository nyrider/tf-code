variable "namePrefix" {
	description = "Prefix for all objects"
	default = "tf-inno-eastus1-dev"
}

variable "ami" {
	description = "AMI for WorkFusion"
	default = "ami-2b8cd851"
}

variable "region" {
	description = "Region for all objects"
	default = "us-east-1"
}


variable "username" {
	default = "adminuser"
}

variable "password" {
	default = "Presby654321"
}

variable "environment" {
  default = "dev"
}

variable "project" {
  default = "innovation vm"
}
