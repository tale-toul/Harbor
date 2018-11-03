#Public subnet1 
output "subnet1_id" {
    value = "${aws_subnet.subnet1.id}"
}

output "subnet2_id" {
    value = "${aws_subnet.subnet2.id}"
}

output "vpc_id" {
    value = "${aws_vpc.vpc.id}"
}

output "sg-ssh-in_id" {
    value = "${aws_security_group.sg-ssh-in.id}"
}

output "sg-ssh-out_id" {
    value = "${aws_security_group.sg-ssh-out.id}"
}

output "sg-ssh-in-local_id" {
    value = "${aws_security_group.sg-ssh-in-local.id}"
}

output "sg-web-out_id" {
    value = "${aws_security_group.sg-web-out.id}"
}

output "sg-web-in-local_id" {
    value = "${aws_security_group.sg-web-in-local.id}"
}

output "sg-web-in-medina_id" {
    value = "${aws_security_group.sg-web-in-medina.id}"
}
