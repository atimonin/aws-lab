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

#--- AMI policy and role ---

data "aws_caller_identity" "my_identity" {}

resource "aws_iam_policy" "nsw_policy" {
    name = "AWSLambdaSwitchLBInstance"
    description = "Policy permitting to switch master-slave instances"
#    path = "/service-role/"
    policy = templatefile("nexus_sw-iam_policy.json", { myAccountId = data.aws_caller_identity.my_identity.account_id } )
}

resource "aws_iam_role" "nsw_role" {
    name = "AWSLambdaSwitchLBInstance"
    description = "Role to switch master-slave instances"
#    path = "/aws-service-role/"
    assume_role_policy = file("nexus_sw-iam_role.json")
    permissions_boundary = "arn:aws:iam::565143587686:policy/DefaultBoundaryPolicy"
}

resource "aws_iam_role_policy_attachment" "nsw_role_policy" {
    role = aws_iam_role.nsw_role.name
    policy_arn = aws_iam_policy.nsw_policy.arn
}

#--- SNS topic (triggering lambda) ---

resource "aws_sns_topic" "nexus_alb_alarms" {
    name = "nexus_alb_alarms"
    display_name = "Nexus ALB alarms"
}

output "nexus_lb_alarms_topic_arn" {
    description = "Nexus alarms SNS topic ARN"
    value = aws_sns_topic.nexus_alb_alarms.arn
}

#--- Clodwatch metric alarm ---

data "aws_lb" "nexus_lb" {
    tags = {
        project = "gridu-aws-practice"
    }
}

data "aws_lb_target_group" "nexus_target_gr" {
#    name = "nexus-lb-target-group"
    tags = {
        project = "gridu-aws-practice"
    }
}

output "nexus_target_gr_arn" {
    description = "Nexus ALB target group ARN"
    value = data.aws_lb_target_group.nexus_target_gr.arn
}

#--- CloudWatch metric alarm to SNS ---

# Namespace = AWS/ApplicationELB
# Metric = HealthyHostCount
# Dimensions = TargetGroup, LoadBalancer
#    Filters the metric data by target group.
#    Specify the target group as follows: targetgroup/<target-group-name>/1234567890123456 (the final portion of the target group ARN).

resource "aws_cloudwatch_metric_alarm" "nexus_alb_alarm" {
    alarm_name = "Nexus-ALB-alarm"
    namespace = "AWS/ApplicationELB"
    metric_name = "HealthyHostCount"
    dimensions = {
        LoadBalancer = data.aws_lb.nexus_lb.arn_suffix
        TargetGroup = data.aws_lb_target_group.nexus_target_gr.arn_suffix
    }
    threshold = "0.5"
    evaluation_periods = 3
    period = 60
    statistic = "Average"
    comparison_operator = "LessThanThreshold"
    actions_enabled = true
    alarm_actions = [ aws_sns_topic.nexus_alb_alarms.arn ]
}

#--- Lambda ---
resource "aws_lambda_function" "nexus_switch" {
    filename = "switch_targets_lambda/lambda-package.zip"
    handler = "lambda_function.lambda_handler"
    function_name = "nexus_sw"
    role = aws_iam_role.nsw_role.arn
    runtime = "python3.7"
    memory_size = "250"
    timeout = 60
    environment {
        variables = {
            ELB_NAME = data.aws_lb.nexus_lb.name
            TG_NAME = data.aws_lb_target_group.nexus_target_gr.name
        }
    }
}

#--- logs retention ---
resource "aws_cloudwatch_log_group" "nexus_lambda_logs" {
    name = "/aws/lambda/${aws_lambda_function.nexus_switch.function_name}"
    retention_in_days = 3
}

resource "aws_lambda_permission" "lambda_sns" {
    statement_id = "AllowExecutionFromSNS"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.nexus_switch.function_name
    principal = "sns.amazonaws.com"
    source_arn = aws_sns_topic.nexus_alb_alarms.arn
}

resource "aws_sns_topic_subscription" "nexus_lambda_sns" {
    topic_arn = aws_sns_topic.nexus_alb_alarms.arn
    protocol = "lambda"
    endpoint = aws_lambda_function.nexus_switch.arn
}

