provider "aws" {
   region     = "ap-south-1"
   access_key = "AKIARMSGJCEVR4MZUONF"
   secret_key = "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"
}

resource "aws_vpc" "tgg_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support     = true
  enable_dns_hostnames   = true
}

resource "aws_subnet" "tgg_subnet" {
  vpc_id                  = aws_vpc.tgg_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
}

resource "aws_security_group" "tgg_security_group" {
  name        = "tgg-security-group"
  description = "Allow SSH access"
  vpc_id      = aws_vpc.tgg_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
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

resource "tls_private_key" "tgg_keypair" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_key_pair" "tgg_keypair" {
  key_name   = "tgg-keypair"
  public_key = tls_private_key.tgg_keypair.public_key_openssh
}


resource "aws_instance" "tgg_instance" {
  count         = 2
  ami           = "ami-03f4878755434977f"
  instance_type = "t2.micro"
  key_name        = "tgg-key"
  subnet_id     = aws_subnet.tgg_subnet.id
  vpc_security_group_ids = [aws_security_group.tgg_security_group.id]
  associate_public_ip_address = true
  #user_data              = file("scripts/init.sh")
  user_data              = "${file("scripts/init.sh")}"

  tags = {
    Name = "tgg-instance"
  }
}



resource "null_resource" "generate_key_file" {
  provisioner "local-exec" {
    command = "echo '${tls_private_key.tgg_keypair.private_key_pem}' > tgg.pem && chmod 600 tgg.pem"
  }
}

resource "aws_internet_gateway" "tgg_igw" {
  vpc_id = aws_vpc.tgg_vpc.id
}

resource "aws_route_table" "tgg_route_table" {
  vpc_id = aws_vpc.tgg_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tgg_igw.id
  }
}

resource "aws_route_table_association" "tgg_subnet_association" {
  subnet_id      = aws_subnet.tgg_subnet.id
  route_table_id = aws_route_table.tgg_route_table.id
}


resource "aws_lb" "tgg_lb" {
  name               = "tgg-lb"
  internal           = false
  load_balancer_type = "network"
  enable_deletion_protection = false

  subnet_mapping {
    subnet_id = aws_subnet.tgg_subnet.id
  }
}

resource "aws_lb_target_group" "tgg_target_group" {
  name     = "tgg-target-group"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.tgg_vpc.id
}

resource "aws_lb_target_group_attachment" "tgg_attachment" {
  count             = length(aws_instance.tgg_instance)
  target_group_arn = aws_lb_target_group.tgg_target_group.arn
  target_id        = aws_instance.tgg_instance[count.index].id
}

resource "aws_alb_listener" "tgg-listener" {
  load_balancer_arn = aws_lb.tgg_lb.id
  port              = "80"
  protocol          = "TCP"
  depends_on        = [aws_lb_target_group.tgg_target_group]

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tgg_target_group.arn
  }
}

output "instance_dns" {
  value = aws_instance.tgg_instance[*].public_dns
}

output "instance_public_ip" {
  value = aws_instance.tgg_instance[*].public_ip
}


output "nlb_dns_name" {
  value = aws_lb.tgg_lb.dns_name
}
