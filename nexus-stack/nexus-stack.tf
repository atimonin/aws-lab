terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
        }
    }
}

provider "aws" {
    profile = "default"
    region = "eu-west-2"  # London
    default_tags {
      tags = {
        student = "atimonin"
      }
    }
}

#----- variable defs (values in .tfvars)-----

variable "vpn_server_cert" {
    type = string
    description = "VPN server side cert ARN"
}

variable "vpn_client_cert" {
    type = string
    description = "VPN client side cert ARN"
}

#---- data sources ----
data "aws_availability_zones" "az" {
    state = "available"
}

data "aws_ami" "nexus_ami" {
    owners = [ "self" ]
#    name_regex = "nexus_template_ami"
    filter {
        name = "name"
        values =[ "nexus_template_ami" ]
    }
}

data "aws_efs_file_system" "nexus_efs" {
    creation_token = "nexus_store"
    tags = {
        student = "atimonin"
    }
}

# ----- networking ------

resource "aws_vpc" "main" { 
    cidr_block = "172.16.0.0/16"
    enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.main.id
}

resource "aws_eip" "nat_eip" {
    count = 2
    vpc = true
    depends_on = [ aws_internet_gateway.igw ]
}

resource "aws_subnet" "public" {
    count = 2
    vpc_id = aws_vpc.main.id
    cidr_block = "172.16.${count.index}.0/24"
    availability_zone = data.aws_availability_zones.az.names[count.index]
    map_public_ip_on_launch = true
    tags = {
        Name = "nexus_public-${count.index}"
    }
}

resource "aws_nat_gateway" "nat" {
    count = 2
    allocation_id = aws_eip.nat_eip[count.index].id
    subnet_id = aws_subnet.public[count.index].id
    depends_on = [ aws_internet_gateway.igw ]
}

resource "aws_subnet" "private" {
    count = 2
    vpc_id = aws_vpc.main.id
    cidr_block = "172.16.${count.index + 2}.0/24"
    availability_zone = data.aws_availability_zones.az.names[count.index]
    map_public_ip_on_launch = false
    tags = {
        Name = "nexus_private-${count.index}"
    }
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "nexus_public"
    }
}

resource "aws_route_table" "private" {
    count = 2
    vpc_id = aws_vpc.main.id
    tags = {
        Name = "nexus_private-${count.index}"
    }
}

resource "aws_route" "public_igw" {
    route_table_id = aws_route_table.public.id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
}

resource "aws_route" "private_nat" {
    count = 2
    route_table_id = aws_route_table.private[count.index].id
    destination_cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat[count.index].id
}

resource "aws_route_table_association" "public" {
    count = 2
    subnet_id = aws_subnet.public[count.index].id
    route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
    count = 2
    subnet_id = aws_subnet.private[count.index].id
    route_table_id = aws_route_table.private[count.index].id
}

#------ VPN -----

resource "aws_ec2_client_vpn_endpoint" "nexus_vpn" {
    description = "OpenVPN endpoint for clients"
    client_cidr_block = "172.17.0.0/22"
    split_tunnel = true
    server_certificate_arn = var.vpn_server_cert
    authentication_options {
        type = "certificate-authentication"
        root_certificate_chain_arn = var.vpn_client_cert
    }
    connection_log_options {
        enabled = false
    }
}

resource "aws_security_group" "nexus_vpn_sg" {
    name = "nexus_vpn_sg"
    vpc_id = aws_vpc.main.id
    ingress {
        from_port = 443
        to_port = 443
        protocol = "udp"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
}

resource "aws_ec2_client_vpn_network_association" "vpn_subnets" {
  count = length(aws_subnet.private)
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.nexus_vpn.id
  subnet_id = aws_subnet.private[count.index].id
  security_groups = [aws_security_group.nexus_vpn_sg.id]
}

resource "aws_ec2_client_vpn_authorization_rule" "vpn_auth_rule" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.nexus_vpn.id
  target_network_cidr = aws_vpc.main.cidr_block
  authorize_all_groups = true
}

output "VPN_dns_name" {
  description = "connection target"
  value = aws_ec2_client_vpn_endpoint.nexus_vpn.dns_name
}

#------ server security groups -------

resource "aws_security_group" "nexus_sg" {
    count = 2
    name = "nexus_sg-${count.index}"
    vpc_id = aws_vpc.main.id
    description = "Allow ssh to nexus and outbound to everywhere (for downloads)"
    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [ "0.0.0.0/0" ]
    }

    ingress {
        from_port = 8081
        to_port = 8081
        protocol = "tcp"
        cidr_blocks = [ aws_subnet.public[count.index].cidr_block ]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
}

#----- EFS -----
resource "aws_security_group" "nexus_efs_sg" {
    name = "EFS_sg"
    vpc_id = aws_vpc.main.id
    description = "Allow inbound NFS from nexus and outbound any"
    ingress {
        from_port = 2049
        to_port = 2049
        protocol = "tcp"
        cidr_blocks = aws_subnet.private[*].cidr_block
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
}

resource "aws_efs_mount_target" "nexus_mount_target" {
    count = 2
    file_system_id = data.aws_efs_file_system.nexus_efs.file_system_id
    security_groups = [ "${aws_security_group.nexus_efs_sg.id}" ]
    subnet_id = aws_subnet.private[count.index].id
}

output "nexus_EFS_store_mount_target_DNS" {
    description = "DNS name for EFS mount_targets"
    value = aws_efs_mount_target.nexus_mount_target[*].dns_name
}

#----- EC2 instances -----

resource "aws_instance" "nexus0" {
    depends_on = [ aws_efs_mount_target.nexus_mount_target[0] ]
    ami = data.aws_ami.nexus_ami.id
    instance_type="t2.small"
    subnet_id = aws_subnet.private[0].id
    vpc_security_group_ids = [ aws_security_group.nexus_sg[0].id ]
    tags = {
        Name = "nexus0"
    }
}

resource "time_sleep" "wait_nexus0_settle" {
    depends_on = [ aws_instance.nexus0 ]
    create_duration = "90s"
    triggers = {
        nexus0_change = "${aws_instance.nexus0.id}"
    }
}

resource "null_resource" "stop_nexus0" {
    depends_on = [ time_sleep.wait_nexus0_settle ]
    provisioner "local-exec" {
        command = <<-EOT
          aws ec2 stop-instances --instance-ids ${aws_instance.nexus0.id}
          aws ec2 wait instance-stopped --instance-ids ${aws_instance.nexus0.id}
        EOT
    }
    triggers = {
        nexus0_change = "${aws_instance.nexus0.id}"
    }
}
            
output "nexus0_info" {
    description = "Info of nexus instance"
    value       = "id:${aws_instance.nexus0.id} priv_ip:${aws_instance.nexus0.private_ip}"
}


resource "aws_instance" "nexus1" {
    depends_on = [ aws_efs_mount_target.nexus_mount_target[1], null_resource.stop_nexus0 ]
    ami = data.aws_ami.nexus_ami.id
    instance_type="t2.small"
    subnet_id = aws_subnet.private[1].id
    vpc_security_group_ids = [ aws_security_group.nexus_sg[1].id ]
    tags = {
        Name = "nexus1"
    }
}

output "nexus1_info" {
    description = "Info of nexus instance"
    value       = "id:${aws_instance.nexus1.id} priv_ip:${aws_instance.nexus1.private_ip}"
}

#----- ALB ------

resource "aws_security_group" "lb_sg" {
    name = "nexus_lb_sg"
    vpc_id = aws_vpc.main.id

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = [ "0.0.0.0/0" ]
    }
}

resource "aws_lb" "nexus_lb" {
    name = "nexus-lb"
    load_balancer_type = "application"
    subnets = aws_subnet.public[*].id
    security_groups = [ aws_security_group.lb_sg.id ]
    tags = {
        project = "gridu-aws-practice"
    }        
}

output "nexus_lb_dns" {
    description = "nexus_lb DNS"
    value = aws_lb.nexus_lb.dns_name
}

resource "aws_lb_target_group" "nexus_targets" {
    name = "nexus-lb-taget-group"
    port = 8081
    protocol = "HTTP"
    vpc_id = aws_vpc.main.id
    stickiness {
        type = "lb_cookie"
    }
    health_check {
        path = "/service/rest/v1/status"
        port = 8081
    }
    tags = {
        project = "gridu-aws-practice"
    }        
}

resource "aws_lb_listener" "nexus_listener" {
    load_balancer_arn = aws_lb.nexus_lb.arn
#    port = 443
#    protocol = "HTTPS"
#    certificate_arn = ....
    port = 80
    protocol = "HTTP"
    default_action {
        target_group_arn = aws_lb_target_group.nexus_targets.arn
        type = "forward"
    }
}

resource "aws_lb_target_group_attachment" "nexus0_target" {
    target_group_arn = aws_lb_target_group.nexus_targets.arn
    target_id = aws_instance.nexus0.id
    port = 8081
}
resource "aws_lb_target_group_attachment" "nexus1_target" {
    target_group_arn = aws_lb_target_group.nexus_targets.arn
    target_id = aws_instance.nexus1.id
    port = 8081
}

