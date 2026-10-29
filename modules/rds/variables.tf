variable "name" {
  description = "Name prefix applied to the instance and every resource this module creates."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID to create the database security group in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the DB subnet group - at least two, in different AZs (RDS requires it even for a single-AZ instance)."
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Security group IDs allowed to reach Postgres on port 5432 - the EKS cluster security group (modules/eks's cluster_security_group_id output), so every pod in the cluster can reach this regardless of which node group it lands on."
  type        = list(string)
}

variable "engine_version" {
  description = "Postgres engine version."
  type        = string
  default     = "17.4"
}

variable "instance_class" {
  description = "RDS instance class - kept small deliberately for a demo database with no real traffic."
  type        = string
  default     = "db.t4g.micro"
}

variable "allocated_storage" {
  description = "Allocated storage in GiB."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Default database name created on the instance."
  type        = string
  default     = "demo"
}

variable "master_username" {
  description = "Master username. Never the password itself - see main.tf's manage_master_user_password."
  type        = string
  default     = "postgres"
}

variable "tags" {
  description = "Extra tags merged onto every resource, in addition to project = build-cache."
  type        = map(string)
  default     = {}
}
