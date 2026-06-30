output "task_definition_arn" {
  description = "ARN of the run-to-exit batch task definition."
  value       = aws_ecs_task_definition.batch.arn
}

output "task_security_group_id" {
  description = "Security group attached to the batch task."
  value       = aws_security_group.task.id
}

output "nightly_schedule_name" {
  description = "EventBridge Scheduler schedule firing the nightly reconciliation."
  value       = aws_scheduler_schedule.nightly.name
}

output "manual_schedule_name" {
  description = "Disabled-by-default schedule for the manual 4am re-run."
  value       = aws_scheduler_schedule.manual.name
}

output "log_group_name" {
  description = "CloudWatch log group for the batch task."
  value       = aws_cloudwatch_log_group.batch.name
}

output "execution_role_arn" {
  description = "ECS execution role ARN (image pull, secret fetch, logs)."
  value       = aws_iam_role.execution.arn
}

output "task_role_arn" {
  description = "ECS task role ARN (least-privilege; logs only)."
  value       = aws_iam_role.task.arn
}
