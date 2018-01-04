provider "aws" {
  region                  = "${var.region}"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "default"
}


# VPC ----------------
module "vpc" {
#    source = "../modules/tf_aws_vpc"
   source = "github.com/terraform-community-modules/tf_aws_vpc"
   name = "${var.namePrefix}-vpc"
   cidr = "10.0.0.0/22"
   public_subnets  = ["10.0.0.0/26","10.0.0.64/26"]
   private_subnets = ["10.0.1.0/26","10.0.1.64/26"]
   azs = ["us-east-1b","us-east-1c"]
   enable_dns_support = true
   enable_dns_hostnames = true
   enable_nat_gateway = true
   tags {
     Name = "${var.namePrefix}-vpc"
     project = "${var.project}"
     environment = "${var.environment}"
   }
}
# End VPC ------------------

# module "tf-ref-vpc" {
#   source = "github.com/azavea/terraform-aws-vpc"
#   name = "tf-ref-vpc"
#   key_name = "tf-test-east1"
#   bastion_ami = "ami-55ef662f"
#   region = "${var.region}"
#   availability_zones = ["us-east-1b","us-east-1c" ]
# }



# Security Groups ------------------------
resource "aws_security_group" "allow_all_outbound" {
    name = "${var.namePrefix}-all-outbound"
    description = "Allow all outbound traffic"
    vpc_id = "${module.vpc.vpc_id}"

    egress = {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
    tags {
      Name = "${var.namePrefix}-all-outbound"
      project = "${var.project}"
      environment = "${var.environment}"
    }
}

resource "aws_security_group" "RDPBastion" {
    name = "${var.namePrefix}-rdp-from-bh"
    description = "Allow RDP traffic from bastion"
    vpc_id = "${module.vpc.vpc_id}"

    ingress = {
        from_port = 3389
        to_port = 3389
        protocol = "tcp"
        cidr_blocks = ["${aws_instance.bastion_host.private_ip}/32"]
#        security_groups =["${module.tf-ref-vpc.bastion_security_group_id}"]
    }
    tags {
      Name = "${var.namePrefix}-rdp-from-bh"
      project = "${var.project}"
      environment = "${var.environment}"
    }
}

resource "aws_security_group" "SSHBastion" {
    name = "${var.namePrefix}-ssh-to-bastion"
    description = "Allow nyp ssh traffic to bastion only"
    vpc_id = "${module.vpc.vpc_id}"

    ingress = {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["143.104.3.0/24"]
    }
    ingress = {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = ["108.29.125.0/24"]
    }
    tags {
      Name = "${var.namePrefix}-ssh-to-bastion"
      project = "${var.project}"
      environment = "${var.environment}"
    }
}


# End Security Groups ------------------------


# Bsation Host -------------------------
resource "aws_instance" "bastion_host" {
  ami           = "ami-55ef662f"
  instance_type = "t2.micro"
  subnet_id     = "${module.vpc.public_subnets[0]}"
  associate_public_ip_address = true
  vpc_security_group_ids = ["${aws_security_group.SSHBastion.id}","${aws_security_group.allow_all_outbound.id}"]
  key_name = "tf-test-east1"
  root_block_device {
    delete_on_termination = "true"
  }
  tags {
    Name = "${var.namePrefix}-bh"
    project = "${var.project}"
    environment = "${var.environment}"
  }
}
# End Bastion Host-----------------------------

# WorkFusion Instance ------------------------
resource "aws_instance" "wf1" {
  ami           = "${var.ami}"
  instance_type = "m4.large"
  subnet_id     = "${module.vpc.private_subnets[0]}"
  vpc_security_group_ids = ["${aws_security_group.RDPBastion.id}","${aws_security_group.allow_all_outbound.id}"]
  root_block_device {
    delete_on_termination = "true"
  }
  tags {
    Name = "${var.namePrefix}-wf1"
    project = "${var.project}"
    environment = "${var.environment}"
  }
}
# End WorkFusion Instance ------------------------
