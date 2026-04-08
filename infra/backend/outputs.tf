output "bucket_name" {
  description = "S3 bucket name — paste this into the main config's backend block"
  value       = aws_s3_bucket.state.id
}

output "dynamodb_table" {
  description = "DynamoDB table name — paste this into the main config's backend block"
  value       = aws_dynamodb_table.lock.name
}
