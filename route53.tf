# The zone is managed by terraform-aws-accounts (accounts/snacker-tracker);
# its records stay with the apps that use them.
data "aws_route53_zone" "khanom_xyz" {
  name = "khanom.xyz"
}

removed {
  from = aws_route53_zone.khanom_xyz

  lifecycle {
    destroy = false
  }
}
