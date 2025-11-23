data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-6.1-x86_64"
}

locals {
  tags = merge(var.tags, {
    "Environment" = var.environment,
    "Module"      = "database",
    "Name"        = var.name
  })

  user_data = templatefile("${path.module}/templates/database.sh", {
    environment             = var.environment
    db_username             = var.db_username
    db_password             = var.db_password
    enable_cloudwatch_agent = var.enable_cloudwatch_agent
  })

  default_ami     = data.aws_ssm_parameter.al2023.value
  effective_ami   = can(regex("^ami-[0-9a-f]+$", var.ami_id)) ? var.ami_id : local.default_ami
}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

resource "aws_security_group" "db" {
  name        = "${var.name}-${var.environment}-db"
  description = "Database security group"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, {
    "Name" = "${var.name}-${var.environment}-db-sg"
  })
}

resource "aws_instance" "db" {
  ami                         = local.effective_ami
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.db.id]
  associate_public_ip_address = false
  user_data                   = base64encode(local.user_data)
  key_name                    = var.key_name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = merge(local.tags, {
    "Name" = "${var.name}-${var.environment}-db"
    "Tier" = "database"
  })
}

resource "aws_ebs_volume" "data" {
  availability_zone = data.aws_subnet.selected.availability_zone
  size              = var.volume_size
  type              = var.volume_type

  tags = merge(local.tags, {
    "Name" = "${var.name}-${var.environment}-db-data"
  })
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.db.id
}

resource "aws_iam_role" "backup" {
  count              = var.enable_backups ? 1 : 0
  name               = "${var.name}-${var.environment}-db-backup"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  count      = var.enable_backups ? 1 : 0
  role       = aws_iam_role.backup[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

data "aws_iam_policy_document" "backup_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_backup_vault" "this" {
  count = var.enable_backups ? 1 : 0
  name  = "${var.name}-${var.environment}-vault"

  tags = merge(local.tags, {
    "Name" = "${var.name}-${var.environment}-vault"
  })
}

resource "aws_backup_plan" "this" {
  count = var.enable_backups ? 1 : 0
  name  = "${var.name}-${var.environment}-plan"

  rule {
    rule_name         = "${var.environment}-daily"
    target_vault_name = aws_backup_vault.this[0].name
    schedule          = "cron(0 3 * * ? *)"
    lifecycle {
      delete_after = var.backup_retention_days
    }
  }

  tags = local.tags
}

resource "aws_backup_selection" "this" {
  count        = var.enable_backups ? 1 : 0
  name         = "${var.environment}-db"
  plan_id      = aws_backup_plan.this[0].id
  iam_role_arn = aws_iam_role.backup[0].arn
  resources    = [aws_instance.db.arn]
}
