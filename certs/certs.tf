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

#--- import certs ---

resource "aws_acm_certificate" "server_cert" {
    private_key = file("aws-endpoint.key")
    certificate_body = file("aws-endpoint.crt")
    certificate_chain = file("ca.crt")
    tags = {
        Name = "aws-endpoint"
    }
}

resource "aws_acm_certificate" "client_cert" {
    private_key = file("atimonin.key")
    certificate_body = file("atimonin.crt")
    certificate_chain = file("ca.crt")
    tags = {
        Name = "client-cert"
    }
}

