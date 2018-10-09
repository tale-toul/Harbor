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

output "bastion_name" {
    value= "${aws_instance.bastion.public_dns}"
}

output "registry_IP" {
    value = "${aws_instance.registry.private_ip}"
}
