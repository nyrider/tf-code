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
resource "aws_cloudwatch_metric_alarm" "cw_alarm1" {
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

# Create an CloudWatch event rule and targets to snapshot an instance when it is stopped ======
resource "aws_cloudwatch_event_rule" "ec2stopped" {
  name        = "snapshot-stopped-ec2-instance"
  description = "Trigger a snapshot of the EBS volume associated to the EC2 Instance that is stopped"
  role_arn = "${aws_iam_role.snapshot_permissions.arn}"
  event_pattern = <<PATTERN
{
  "source": [
    "aws.ec2"
  ],
  "detail-type": [
    "EC2 Instance State-change Notification"
  ],
  "detail": {
    "state": [
      "stopped"
    ],
    "instance-id": [
      "${aws_instance.wf1.id}"
    ]
  }
}
PATTERN
}

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

resource "aws_cloudwatch_event_target" "snap" {
  rule      = "${aws_cloudwatch_event_rule.ec2stopped.name}"
  target_id = "SnapshotEC2Stopped"
  arn       = "arn:aws:automation:${var.region}:${var.account_id}:action/EBSCreateSnapshot/StoppedInstanceSnap"
  input = "${jsonencode("arn:aws:ec2:${var.region}:${var.account_id}:volume/${aws_instance.wf1.root_block_device.0.volume_id}")}"
#  role_arn = "${aws_iam_role.snapshot_permissions.arn}"
}



resource "aws_iam_role" "snapshot_permissions" {
  name = "NYP_Snapshot_stopped_EC2_instance"
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
    name        = "example-snapshot-policy"
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
    sid = "tfec2start"

    actions = [
      "ec2:StartInstances",
    ]

    resources = [
      "arn:aws:ec2:*:${var.account_id}:instance/*",
    ]
  }
}
#   "arn:aws:ec2:*:${var.account_id}:instance/${aws_instance.wf1.id}",


resource "aws_iam_policy" "ec2_role_policy" {
  name   = "${var.namePrefix}_start_wf_instance_policy"
  path   = "/"
  policy = "${data.aws_iam_policy_document.ec2_policy.json}"
}

resource "aws_iam_role" "ec2_role" {
  name = "${var.namePrefix}_start_ec2_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
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
  name   = "${var.namePrefix}_assume_start_wf_instance_role"
  path   = "/"
  policy = "${data.aws_iam_policy_document.assume_policy.json}"
}

# End Create policy to allow starting wf instance =============












output "Instance " {
  value = "${aws_instance.wf1.id}"
}
# End Cloudwatch Alarm to stop instance after idle period -------------
