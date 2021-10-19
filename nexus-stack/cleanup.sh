#!/bin/sh

terraform destory -vaf-file=nexus-stack.tfvars -auto-approve

eval "$(cat nexus-stack.tfvars | tr -d ' ')"

#aws acm delete-certificate --certificate-arn ${vpn_server_cert}
#aws acm delete-certificate --certificate-arn ${vpn_client_cert}

