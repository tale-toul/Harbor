provider "aws" {
    region = "eu-west-1"
    version = "~> 1.41"
}

provider "template" {
    version = "~> 1.0"
}

#Bucket name
variable "bucket_name" {
    description = "The name of the bucket to use as a backend storage, must be unique across all AWS"
    default = "harbor-s3-store-backend"
}

#IAM user
resource "aws_iam_user" "harbor_s3_user" {
    name = "harbor_s3_user"
}

#IAM user access key
resource "aws_iam_access_key" "harbor_s3_user_ak" {
    user = "${aws_iam_user.harbor_s3_user.name}"
}

#Bucket policy file 
data "template_file" "bucket_policy" {
    template = "${file("bucket-policy.tp")}"

    vars {
        user = "${aws_iam_user.harbor_s3_user.arn}"
        name = "${var.bucket_name}"
    }
}

#S3 bucket
resource "aws_s3_bucket" "registry_bucket" {
    bucket = "${var.bucket_name}"
    policy = "${data.template_file.bucket_policy.rendered}"
    force_destroy = true

    tags {
        Name = "registry_bucket"
        Project = "harbor"
    }
}
