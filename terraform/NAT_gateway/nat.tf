provider "aws" {
    region = "eu-west-1"
    version = "~> 1.39"
}

data "terraform_remote_state" "vpc" {
    backend = "local"

    config {
        path = "../terraform.tfstate"
    }
}

#EIP
resource "aws_eip" "nateip" { }

#NAT GATEWAY
resource "aws_nat_gateway" "natgw" {
    allocation_id = "${aws_eip.nateip.id}"
    subnet_id = "${data.terraform_remote_state.vpc.subnet1_id}"
}
