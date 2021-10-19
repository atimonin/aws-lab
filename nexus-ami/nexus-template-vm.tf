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
}

variable "nexus_template_keyname" {
    type = string
    description = "ssh key name (should alredy exist in AWS)"
}

data "aws_availability_zones" "az" {
    state = "available"
}

resource "aws_default_subnet" "default_subnet_az0" {
   availability_zone = data.aws_availability_zones.az.names[0]
}

output "AZ0" {
    description = "AZ[0] name"
    value = data.aws_availability_zones.az.names[0]
}

output "subnet_az0" {
    description = "default subnet in AZ[0]"
    value = "id: ${aws_default_subnet.default_subnet_az0.id} CIDR: ${aws_default_subnet.default_subnet_az0.cidr_block}"
}

resource "aws_efs_file_system" "nexus_store" {
    creation_token = "nexus_store"
    tags = {
        student = "atimonin"
        project = "gridu-aws-practice"
    }
}

output "nexus_EFS_store_DNS" {
    description = "DNS name for EFS endpoint"
    value = aws_efs_file_system.nexus_store.dns_name
}

output "nexus_EFS_store_id" {
    description = "ID of EFS nexus store"
    value =  aws_efs_file_system.nexus_store.id
}

resource "aws_security_group" "nexus_template_sg" {
    name = "nexus_template_allow_ssh"
    description = "Allow ssh to nexus_template and outbound to everywhere (for downloads)"
    ingress {
            from_port = 0
            to_port = 22
            protocol = "tcp"
            cidr_blocks = [ "0.0.0.0/0" ]
        }

    egress {
            from_port = 0
            to_port = 0
            protocol = "-1"
            cidr_blocks = [ "0.0.0.0/0" ]
            ipv6_cidr_blocks = ["::/0"]
        }
    tags = {
        student = "atimonin"
    }
}

resource "aws_security_group" "nexus_efs_sg" {
    name = "EFS_sg"
    description = "Allow inbound from nexus_template and outbound any"
    ingress {
        security_groups = [ "${aws_security_group.nexus_template_sg.id}" ]
        from_port = 2049
        to_port = 2049
        protocol = "tcp"
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
    }
    tags = {
        student = "atimonin"
    }
}

resource "aws_efs_mount_target" "nexus_mount_target" {
    file_system_id = "${aws_efs_file_system.nexus_store.id}"
    security_groups = [ "${aws_security_group.nexus_efs_sg.id}" ]
    subnet_id = aws_default_subnet.default_subnet_az0.id
}

output "nexus_EFS_store_mount_target_DNS" {
    description = "DNS name for EFS mount_target"
    value = aws_efs_file_system.nexus_store.dns_name
}

resource "aws_instance" "nexus_template" {
    ami = "ami-0194c3e07668a7e36"
    instance_type="t2.small"
    key_name = var.nexus_template_keyname
    subnet_id = aws_default_subnet.default_subnet_az0.id
    vpc_security_group_ids = [ aws_security_group.nexus_template_sg.id ]
    tags = {
        student = "atimonin"
        Name = "nexus_template_instance"
    }
#   wait for sshd ready
    provisioner "remote-exec" {
        inline = [ "# ssh connected!" ]
        connection {
            type = "ssh"
            user = "ubuntu"
            private_key = file(pathexpand("~/.ssh/id_rsa"))
            host = self.public_ip
        }
    }
    
    provisioner "local-exec" {
        command = "ansible-playbook -i inv.aws.aws_ec2.yml -e nexus_mount_dns=${aws_efs_mount_target.nexus_mount_target.dns_name} nexus-template.yml"
    }
}

output "nexus_template_instance_id" {
    description = "ID of nexus_template"
    value       = aws_instance.nexus_template.id
}

output "nexus_template_public_ip" {
  description = "Public IP address of the nexus"
  value       = aws_instance.nexus_template.public_ip
}

resource "aws_ami_from_instance" "nexus_template_ami" {
    name = "nexus_template_ami"
    source_instance_id = aws_instance.nexus_template.id
    tags = {
        student = "atimonin"
        project = "gridu-aws-practice"
    }
}

output "nexus_ami_id" {
  description = "AMI id of nexus image"
  value = aws_ami_from_instance.nexus_template_ami.id
}
