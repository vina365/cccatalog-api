# Internal URL for interacting with Ingestion Server API
resource "aws_route53_zone" "ingestion-private-dns" {
  name = "ingestion.private"
  vpc_id = "vpc-b741b4cc"
}

resource "aws_route53_record" "ingestion-private-a-record" {
  name    = "ingestion.private"
  type    = "A"
  ttl     = 120
  records = ["${aws_instance.ingestion-server-ec2.private_ip}"]
  zone_id = "${aws_route53_zone.ingestion-private-dns.id}"
}

# A templated bash script that bootstraps the docker daemon and runs a container.
data "template_file" "init"{
  template = "${file("${path.module}/init.tpl")}"

  # Templated variables passed to initialization script.
  vars {
    aws_access_key_id     = "${var.aws_access_key_id}"
    aws_secret_access_key = "${var.aws_secret_access_key}"
    elasticsearch_url     = "${var.elasticsearch_url}"
    elasticsearch_port    = "${var.elasticsearch_port}"
    aws_region            = "${var.aws_region}"
    database_host         = "${var.database_host}"
    database_password     = "${var.database_password}"
    database_port         = "${var.database_port}"
    db_buffer_size        = "${var.db_buffer_size}"
    copy_tables           = "${var.copy_tables}"
    poll_interval         = "${var.poll_interval}"
    staging_environment   = "${var.environment}"
    upstream_db_host      = "${var.upstream_db_host}"
    upstream_db_password  = "${var.upstream_db_password}"

    docker_tag            = "${var.docker_tag}"
  }
}

# VPC subnets
data "aws_subnet_ids" "subnets" {
  vpc_id = "${var.vpc_id}"
}

resource "aws_security_group" "ingestion-server-sg" {
  name_prefix = "ingestion-server-sg-${var.environment}"
  vpc_id = "${var.vpc_id}"

  # Allow incoming SSH from the internet
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow incoming traffic from the internal network
  ingress {
    from_port   = 8001
    to_port     = 8001
    protocol    = "tcp"
    cidr_blocks = ["172.30.0.0/16"]
  }

  # Unrestricted egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ingestion-server-ec2" {
  ami                    = "ami-b70554c8"
  instance_type          = "${var.instance_type}"
  user_data              = "${data.template_file.init.rendered}"
  # Launch it on the first available subnet
  subnet_id              = "${element(data.aws_subnet_ids.subnets.ids, 0)}"
  key_name               = "cccapi-admin"
  vpc_security_group_ids = ["${aws_security_group.ingestion-server-sg.id}"]

  tags {
    Name        = "ingestion-server-${var.environment}"
    environment = "${var.environment}"
  }
}