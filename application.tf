/*
  ======================================================
    'SECURITY GROUPS'
  ======================================================
*/

# security for the load balancer
resource "aws_security_group" "elb" {
  name        = "havoc-elb-sg"
  description = "HAVOC ELB SG"
  vpc_id      = aws_vpc.default.id

  # world accesible on 443
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
    # force an interpolation expression to be interpreted as a list by wrapping it
    # in an extra set of list brackets. That form was supported for compatibility in
    # v0.11, but is no longer supported in Terraform v0.12.
    #
    # If the expression in the following list itself returns a list, remove the
    # brackets to avoid interpretation as a list of lists. If the expression
    # returns a single list item then leave it as-is and remove this TODO comment.
    cidr_blocks = [var.vpc_cidrs["VPC"]]
  }

  tags = {
    Name = "HAVOC-SG-ELB"
  }
}

# security for the autoscaled instances
resource "aws_security_group" "ec2" {
  name        = "havoc-ec2-sg"
  description = "HAVOC EC2 SG"
  vpc_id      = aws_vpc.default.id

  # anyone within the VPC can ssh in
  ingress {
    from_port = 22
    to_port   = 22
    protocol  = "tcp"
    # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
    # force an interpolation expression to be interpreted as a list by wrapping it
    # in an extra set of list brackets. That form was supported for compatibility in
    # v0.11, but is no longer supported in Terraform v0.12.
    #
    # If the expression in the following list itself returns a list, remove the
    # brackets to avoid interpretation as a list of lists. If the expression
    # returns a single list item then leave it as-is and remove this TODO comment.
    cidr_blocks = [var.vpc_cidrs["VPC"]]
  }

  # only the load-balancer needs to read port 8080 (our web app)
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [aws_security_group.elb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HAVOC-SG-EC2"
  }
}

/*
  ======================================================
    'MAIN LOAD BALANCER'
  ======================================================
*/

resource "aws_elb" "default" {
  subnets                     = [aws_subnet.ext1.id, aws_subnet.ext2.id]
  security_groups             = [aws_security_group.elb.id]
  cross_zone_load_balancing   = true
  idle_timeout                = 60
  connection_draining         = true
  connection_draining_timeout = 60

  # forward 443 terminated HTTPS traffic to port 8080 on the instances
  listener {
    instance_port     = 8080
    instance_protocol = "http"
    lb_port           = 443
    lb_protocol       = "https"

    # attach our ready `*.racker.tech` cert to this listener
    ssl_certificate_id = "arn:aws:acm:us-east-1:595430538023:certificate/5d611a4a-6348-4134-9ccd-4b92e25469ac"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    target              = "HTTP:8080/"
    interval            = 30
  }

  tags = {
    Name = "HAVOC-ELB"
  }
}

/*
  ======================================================
    'AUTOSCALING AND LAUNCH CONFIG'
  ======================================================
*/

# TODO: smooth out handling of extant keypair
resource "aws_key_pair" "default" {
  key_name   = var.key_name
  public_key = file(var.public_key_path)
}

resource "aws_launch_configuration" "default" {
  image_id          = var.aws_amis[var.aws_region]
  instance_type     = "t2.small"
  security_groups   = [aws_security_group.ec2.id]
  key_name          = var.key_name
  enable_monitoring = true

  # this tells TERRAFORM to create a new launch_config before swapping it out at the ASG
  # otherwise you get an error because you cannot delete while it is in use.
  lifecycle {
    create_before_destroy = true
  }

  # using PACKER to prepare AMI's haven't needed userdata yet; here for demonstration.
  user_data = file("userdata.sh")
}

# launch instances in both subnets provided and place them into the load balancer
resource "aws_autoscaling_group" "default" {
  vpc_zone_identifier       = [aws_subnet.int1.id, aws_subnet.int2.id]
  max_size                  = 6
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  load_balancers            = [aws_elb.default.name]
  launch_configuration      = aws_launch_configuration.default.name

  tag {
    key                 = "Name"
    value               = "HAVOC-DEV"
    propagate_at_launch = true
  }
}

/*
  ======================================================
    'DNS MANAGEMENT'
  ======================================================
*/

# create an alias record on the extant zone for this ELB
resource "aws_route53_record" "default" {
  zone_id = "Z2EBPSP8GXVCP4"
  name    = "havoc.racker.tech"
  type    = "A"

  alias {
    name                   = aws_elb.default.dns_name
    zone_id                = aws_elb.default.zone_id
    evaluate_target_health = true
  }
}

