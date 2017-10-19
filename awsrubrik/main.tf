provider "aws" {
  region                  = "us-west-2"
  shared_credentials_file = ".../.aws/credentials"
  profile                 = "default"
}

resource "aws_s3_bucket" "tf333-rubrik-log-bucket" {
  bucket = "tf333-rubrik-log-bucket"
  acl    = "log-delivery-write"
  force_destroy = true
}

resource "aws_s3_bucket" "tf333-rubrik-bucket" {
  bucket = "tf333-rubrik-bucket"
  acl    = "private"
  force_destroy = true

  logging {
    target_bucket = "${aws_s3_bucket.tf333-rubrik-log-bucket.id}"
    target_prefix = "log"
  }

  lifecycle_rule {
    id      = "oldfiles"
    enabled = true

    expiration {
      days = 60
    }
  }

}

resource "aws_sns_topic" "topic" {
  name = "tf-s3-event-notification-topic"

  policy = <<POLICY
{
    "Version":"2012-10-17",
    "Statement":[{
        "Effect": "Allow",
        "Principal": {"AWS":"*"},
        "Action": "SNS:Publish",
        "Resource": "arn:aws:sns:*:*:tf-s3-event-notification-topic",
        "Condition":{
            "ArnLike":{"aws:SourceArn":"${aws_s3_bucket.tf333-rubrik-bucket.arn}"}
        }
    }]
}
POLICY
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = "${aws_s3_bucket.tf333-rubrik-bucket.id}"

  topic {
    topic_arn     = "${aws_sns_topic.topic.arn}"
    events        = ["s3:ObjectCreated:*"]
  }
}

output "bucket_domain_name" {
  value = "${aws_s3_bucket.tf333-rubrik-bucket.bucket_domain_name}"
}
