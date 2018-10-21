#Access key ID
output "iam_user_access_key" {
    value = "${aws_iam_access_key.harbor_s3_user_ak.id}"
}

output "iam_user_secret_key" {
    value = "${aws_iam_access_key.harbor_s3_user_ak.secret}"
}

output "bucket_region" {
    value = "${aws_s3_bucket.registry_bucket.region}"
}

output "bucket_name" {
    value = "${aws_s3_bucket.registry_bucket.id}"
}
