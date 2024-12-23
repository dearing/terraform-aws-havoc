/*
  ======================================================
    'SCALING POLICES'
  ======================================================
*/

# POLICY to STEP UP by a third
resource "aws_autoscaling_policy" "step-up" {
  adjustment_type          = "PercentChangeInCapacity"
  autoscaling_group_name   = aws_autoscaling_group.default.name
  cooldown                 = 60
  min_adjustment_magnitude = 1
  name                     = "step up"
  scaling_adjustment       = 33
}

# POLICY to STEP DOWN by a third
resource "aws_autoscaling_policy" "step-down" {
  adjustment_type          = "PercentChangeInCapacity"
  autoscaling_group_name   = aws_autoscaling_group.default.name
  cooldown                 = 60
  min_adjustment_magnitude = 1
  name                     = "step down"
  scaling_adjustment       = -33
}

/*
  ======================================================
    'SCHEDULES'
  ======================================================
*/

# SCHEDULE to lower count to 2 at the top of ever hour
resource "aws_autoscaling_schedule" "default" {
  scheduled_action_name  = "fresh and clean"
  min_size               = 2
  max_size               = 6
  desired_capacity       = 2
  recurrence             = "0 * * * *" # hourly
  autoscaling_group_name = aws_autoscaling_group.default.name
}

/*
  ======================================================
    'CLOUD WATCH ALARMS'
  ======================================================
*/

# ALARM for CPU > 75% over 2 minutes; calls STEP-UP
resource "aws_cloudwatch_metric_alarm" "hot" {
  alarm_name          = "heating-up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "75"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.default.name
  }
  alarm_description = "when the average cpu usage rises, scale up"
  alarm_actions     = [aws_autoscaling_policy.step-up.arn]
}

# ALARM for CPU < 25% over 2 minutes; CALLS STEP-DOWN
resource "aws_cloudwatch_metric_alarm" "cool" {
  alarm_name          = "cooling-off"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = "60"
  statistic           = "Average"
  threshold           = "25"
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.default.name
  }
  alarm_description = "when the average cpu usage drops, scale down"
  alarm_actions     = [aws_autoscaling_policy.step-down.arn]
}

