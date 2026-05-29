################################################################################
# ALB + web/app-tier Auto Scaling Groups — four findings remediated in one
# module:
#   REL-03  : ASG health_check_type = ELB + ALB /app/health probe
#   PERF-03 : ALB idle_timeout = 300
#   PERF-04 : Web tier t3.large → m5.large (non-burstable)
#   COST-05 : Detailed monitoring retained only on the app tier
################################################################################

############################
# ALB — PERF-03 idle_timeout 300s
############################

resource "aws_lb" "this" {
  name               = "plm-app-${var.environment}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_sg_id]
  subnets            = var.public_subnet_ids

  idle_timeout                     = 300   # PERF-03 — was 60 (default)
  enable_deletion_protection       = true
  enable_http2                     = true
  drop_invalid_header_fields       = true

  access_logs {
    bucket  = var.access_log_bucket
    prefix  = "alb-plm-app"
    enabled = true
  }

  tags = merge(var.tags, { Findings = "PERF-03" })
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.this.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

############################
# Web-tier target group — REL-03 health check probes /app/health
############################

resource "aws_lb_target_group" "web" {
  name             = "plm-app-web-${var.environment}"
  port             = 443
  protocol         = "HTTPS"
  vpc_id           = var.vpc_id
  target_type      = "instance"
  deregistration_delay = 60

  health_check {
    enabled             = true
    path                = "/app/health"
    matcher             = "200"
    protocol            = "HTTPS"
    port                = "traffic-port"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  stickiness {
    enabled = true
    type    = "lb_cookie"
    cookie_duration = 3600
  }

  tags = merge(var.tags, { Finding = "REL-03" })
}

############################
# Launch templates
############################

# Web tier — PERF-04 — m5.large (non-burstable, eliminates CPU credit exhaustion)
resource "aws_launch_template" "web" {
  name_prefix   = "plm-app-web-${var.environment}-"
  image_id      = var.web_ami_id
  instance_type = "m5.large"

  iam_instance_profile { name = var.app_instance_profile_name }
  vpc_security_group_ids = [var.web_sg_id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 100
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = var.ebs_kms_key_arn
    }
  }

  monitoring {
    enabled = false   # COST-05 — web tier on basic (5-min) monitoring
  }

  metadata_options {
    http_tokens                 = "required"   # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Tier = "web", Findings = "PERF-04 COST-05" })
  }

  user_data = base64encode(var.web_user_data)
}

# App tier — m5.xlarge retained; detailed monitoring kept for perf investigation
resource "aws_launch_template" "app" {
  name_prefix   = "plm-app-app-${var.environment}-"
  image_id      = var.app_ami_id
  instance_type = "m5.xlarge"

  iam_instance_profile { name = var.app_instance_profile_name }
  vpc_security_group_ids = [var.app_sg_id]

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 100
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = var.ebs_kms_key_arn
    }
  }

  monitoring {
    enabled = true   # COST-05 — app tier keeps 1-min monitoring (perf debugging)
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Tier = "app" })
  }

  user_data = base64encode(var.app_user_data)
}

############################
# Auto Scaling Groups — REL-03 — health_check_type = ELB
############################

resource "aws_autoscaling_group" "web" {
  name                      = "plm-app-web-${var.environment}"
  min_size                  = 2
  desired_capacity          = 2
  max_size                  = 6
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = [aws_lb_target_group.web.arn]
  health_check_type         = "ELB"          # REL-03
  health_check_grace_period = 300            # 5 min for app startup
  default_cooldown          = 300
  termination_policies      = ["OldestLaunchTemplate", "OldestInstance"]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
      instance_warmup        = 300
    }
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = "plm-app-web-${var.environment}", Tier = "web", Finding = "REL-03 PERF-04" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "plm-app-app-${var.environment}"
  min_size                  = 2
  desired_capacity          = 2
  max_size                  = 6
  vpc_zone_identifier       = var.private_subnet_ids
  health_check_type         = "ELB"
  health_check_grace_period = 300
  default_cooldown          = 300
  termination_policies      = ["OldestLaunchTemplate", "OldestInstance"]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = merge(var.tags, { Name = "plm-app-app-${var.environment}", Tier = "app", Finding = "REL-03" })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
