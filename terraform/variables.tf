variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "ami_id" {
  description = "Ubuntu AMI for the region"
  type        = string
}

variable "ssh_key_name" {
  description = "Name of the AWS key pair for SSH access"
  type        = string
}

variable "admin_ip" {
  description = "Your IP in CIDR notation for SSH access (e.g. 203.0.113.5/32)"
  type        = string
}
