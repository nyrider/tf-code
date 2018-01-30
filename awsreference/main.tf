provider "aws" {
  region                  = "${var.region}"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "default"
}



# VPC ----------------
module "vpc" {
  source = "github.com/terraform-aws-modules/terraform-aws-vpc.git" # "github.com/terraform-community-modules/tf_aws_vpc"
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

# Cloudwatch Alarm to stop instance after idle period -------------
resource "aws_cloudwatch_metric_alarm" "foobar" {
  alarm_name                = "tf-nyp-useast1-stop after idle"
  comparison_operator       = "LessThanOrEqualToThreshold"
  evaluation_periods        = "3"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "300"
  statistic                 = "Average"
  threshold                 = "5"
  actions_enabled           = "true"
  treat_missing_data        = "breaching"
  alarm_actions             = ["arn:aws:sns:us-east-1:171061125909:instance-idle-alert","arn:aws:automate:us-east-1:ec2:stop"]
  ok_actions                = ["arn:aws:sns:us-east-1:171061125909:instance-idle-alert"]
  dimensions {
#     instanceid   = "${aws_instance.wf1.id}"
#     instancename =	tf-inno-eastus1-dev-wf1
  #    Name = "InstanceId"
  #    Value   = "${aws_instance.wf1.id}"
      InstanceId = "${aws_instance.wf1.id}"
  }
  #     alarm_actions = 2
  #     alarm_actions = "arn:aws:sns:us-east-1:171061125909:instance-idle-alert"
  #     alarm_actions = "arn:aws:automate:us-east-1:ec2:stop"
  #     actions_enabled   = "true"
  # }
  alarm_description         = "Monitors ec2 cpu utilization for idle time"
#  insufficient_data_actions = []
}

output "Instance " {
  value = "${aws_instance.wf1.id}"
}
# End Cloudwatch Alarm to stop instance after idle period -------------
