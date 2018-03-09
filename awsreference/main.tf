provider "aws" {
  region                  = "${var.region}"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "default-mlang"
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
  count = "${var.cnt}"
  vpc_security_group_ids = ["${aws_security_group.RDPBastion.id}","${aws_security_group.allow_all_outbound.id}"]
  root_block_device {
    delete_on_termination = "true"
  }
  tags {
    Name = "${var.namePrefix}-wf-${count.index}"
    project = "${var.project}"
    environment = "${var.environment}"
  }
}
# End WorkFusion Instance ------------------------

# Cloudwatch Alarm to stop instance after idle period -------------
resource "aws_cloudwatch_metric_alarm" "cw_alarm1" {
  count = "${var.cnt}"
  alarm_name                = "tf-nyp-useast1-stop after idle-${count.index}"
  comparison_operator       = "LessThanOrEqualToThreshold"
  evaluation_periods        = "3"
  metric_name               = "CPUUtilization"
  namespace                 = "AWS/EC2"
  period                    = "60"
  statistic                 = "Average"
  threshold                 = "10"
  actions_enabled           = "true"
  treat_missing_data        = "breaching"
  alarm_actions             = ["arn:aws:sns:us-east-1:171061125909:instance-idle-alert","arn:aws:automate:us-east-1:ec2:stop"]
  ok_actions                = ["arn:aws:sns:us-east-1:171061125909:instance-idle-alert"]
  dimensions {
#     instanceid   = "${aws_instance.wf1.id}"
#     instancename =	tf-inno-eastus1-dev-wf1
  #    Name = "InstanceId"
  #    Value   = "${aws_instance.wf1.id}"
      InstanceId = "${element(aws_instance.wf1.*.id, count.index)}"#"${aws_instance.wf1.*.id}"
  }
  #     alarm_actions = 2
  #     alarm_actions = "arn:aws:sns:us-east-1:171061125909:instance-idle-alert"
  #     alarm_actions = "arn:aws:automate:us-east-1:ec2:stop"
  #     actions_enabled   = "true"
  # }
  alarm_description         = "Monitors ec2 cpu utilization for idle time"
#  insufficient_data_actions = []
}
# End Cloudwatch Alarm to stop instance after idle period -------------


# Create CloudWatch event rule and targets to snapshot an instance when it is stopped ======
data "template_file" "event-pattern-template" {
    template = "${file("../templates/eventpattern.tpl")}"
#    vars {
#        instanceid1= "${aws_instance.wf1.0.id}"
#        instanceid2= "${aws_instance.wf1.1.id}"  #"${element(aws_instance.wf1.*.id, count.index)}"
#    }
    vars {
      instanceid = "${replace( join(",", aws_instance.wf1.*.id), ",",  "\",\"")}"
      # instanceid = "${join(",", aws_instance.wf1.*.id)}"
    }
}

resource "aws_cloudwatch_event_rule" "ec2stopped" {
  name        = "${var.namePrefix}-snapshot-stopped-ec2-instance"
  description = "Trigger a snapshot of the EBS volume associated to the EC2 Instance that is stopped"
  role_arn = "${aws_iam_role.snapshot_permissions.arn}"
  event_pattern = "${data.template_file.event-pattern-template.rendered}"
}

# "${aws_instance.wf1.id}",

resource "aws_cloudwatch_event_target" "sns" {
  rule      = "${aws_cloudwatch_event_rule.ec2stopped.name}"
  target_id = "SendToSNS"
  arn       = "arn:aws:sns:us-east-1:171061125909:instance-idle-alert"
  input_transformer  {
    input_template = <<EOF
"The EC2 instance <instance> has changed state to <state>. A snapshot of the EBS volume will be created"
EOF
    input_paths = {
      instance = "$.detail.instance-id"
      state = "$.detail.state"
    }
  }
}

# data "template_file" "example" {
#   count = "${var.cnt}"
#   template = "aws_instance.wf1.${count.index}.root_block_device.0.volume_id"
# }

data "aws_ebs_volume" "ebs_volume" {
  count = "${var.cnt}"

  filter {
    name   = "attachment.instance-id"
    values = ["${element(aws_instance.wf1.*.id, count.index)}"]
  }
}


resource "aws_cloudwatch_event_target" "snap" {
  count     = "${var.cnt}"
  rule      = "${aws_cloudwatch_event_rule.ec2stopped.name}"
  target_id = "SnapshotEC2Stopped-${count.index}"
  arn       = "arn:aws:automation:${var.region}:${var.account_id}:action/EBSCreateSnapshot/StoppedInstanceSnap"
  input = "${jsonencode("arn:aws:ec2:${var.region}:${var.account_id}:volume/${data.aws_ebs_volume.ebs_volume.*.id[count.index]}")}"
#  input = "${jsonencode("arn:aws:ec2:${var.region}:${var.account_id}:volume/${aws_instance.wf1.0.root_block_device.0.volume_id}")}"
#  role_arn = "${aws_iam_role.snapshot_permissions.arn}"
}




resource "aws_iam_role" "snapshot_permissions" {
  name = "${var.namePrefix}-snapshot-stopped-ec2-instance"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "automation.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "snapshot_policy" {
    name        = "${var.namePrefix}-snapshot-policy"
    description = "grant ebs snapshot permissions to cloudwatch event rule"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:RebootInstances",
        "ec2:StopInstances",
        "ec2:TerminateInstances",
        "ec2:CreateSnapshot"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "snapshot_policy_attach" {
    role       = "${aws_iam_role.snapshot_permissions.name}"
    policy_arn = "${aws_iam_policy.snapshot_policy.arn}"
}
# End # Create an CloudWatch event rule and targets to snapshot an instance when it is stopped ======

# Create policy to allow starting wf instance =============
data "aws_iam_policy_document" "ec2_policy" {
  statement {
    sid = "tfec2start0"
    actions = [
      "ec2:StartInstances",
    ]
    resources = [
      "arn:aws:ec2:${var.region}:${var.account_id}:instance/*",
    ]
  }
  statement {
    sid = "tfec2start1"
    actions = [
      "ec2:DescribeInstances",
    ]
    resources = [
      "*",
    ]
  }
}
#   "arn:aws:ec2:*:${var.account_id}:instance/${aws_instance.wf1.id}",
# "arn:aws:ec2:*:${var.account_id}:instance/${aws_instance.wf1.*.id[0]}",

resource "aws_iam_policy" "ec2_role_policy" {
  name   = "${var.namePrefix}-start-wf-instance_policy"
  path   = "/"
  policy = "${data.aws_iam_policy_document.ec2_policy.json}"
}

data "template_file" "assume-policy-template" {
    template = "${file("../templates/assumerole.tpl")}"
    vars {
        account = "${var.account_id}"
    }
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.namePrefix}-start-wf-role"

  assume_role_policy = "${data.template_file.assume-policy-template.rendered}"
}

resource "aws_iam_role_policy_attachment" "test-attach" {
    role       = "${aws_iam_role.ec2_role.name}"
    policy_arn = "${aws_iam_policy.ec2_role_policy.arn}"
}


data "aws_iam_policy_document" "assume_policy" {
  statement {
    sid = "tfec2start"

    actions = [
      "sts:AssumeRole",
    ]

    resources = [
      "${aws_iam_role.ec2_role.arn}",
    ]
  }
}

resource "aws_iam_policy" "assume_role_policy" {
  name   = "${var.namePrefix}-assume-start-wf-instance_role"
  path   = "/"
  policy = "${data.aws_iam_policy_document.assume_policy.json}"
}

data "aws_iam_policy_document" "temp_ec2_policy" {
  statement {
    sid = "tfec2start3"

    actions = [
      "sts:AssumeRole",
    ]

    resources = [
      "arn:aws:iam::171061125909:role/tf-inno-eastus1-dev-start-wf-role",
    ]
  }
}
# ${aws_instance.wf1.id}
#      "arn:aws:iam::${var.account_id}:role/tf-inno-eastus1-dev_developer",
resource "aws_iam_policy" "ec2_user_role_policy" {
  name   = "${var.namePrefix}-assume-user-role"
  path   = "/"
  policy = "${data.aws_iam_policy_document.temp_ec2_policy.json}"
}
# End Create policy to allow starting wf instance =============

# Create IAM user and associate policy to let them assume role
resource "aws_iam_user" "iu" {
  name = "inno2"
}

resource "aws_iam_access_key" "uikey" {
  user = "${aws_iam_user.iu.name}"
}

resource "aws_iam_user_policy_attachment" "test-attach" {
    user       = "${aws_iam_user.iu.name}"
    policy_arn = "${aws_iam_policy.ec2_user_role_policy.arn}"
}
# End Create IAM user and associate policy to let them assume role


# Outputs -----------------------------------------------------------
output "Instances: " {
  value = "${aws_instance.wf1.*.id}"
}

output "iuaccess: " {
  value = "${aws_iam_access_key.uikey.id}"
}

output "iusecret: " {
  value = "${aws_iam_access_key.uikey.secret}"
}

output "data-test: " {
  value = "${data.aws_ebs_volume.ebs_volume.*.id}"
}
# End Outputs -----------------------------------------------------------
