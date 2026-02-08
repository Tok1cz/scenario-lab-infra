resource "aws_instance" "app" {
  ami                    = var.ami_id
  instance_type          = "t3.nano"
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.app.id]
  tags                   = { Name = "scenario-lab" }
}

resource "aws_security_group" "app" {
  name = "scenario-lab-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
}
