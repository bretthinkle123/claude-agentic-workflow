# Declares the Application Load Balancer in front of the app — the topology that makes
# request.client.host meaningless without forwarded-header trust.
resource "aws_lb" "app" {
  name               = "app-alb"
  load_balancer_type = "application"
  internal           = false
}

resource "aws_lb_target_group" "app" {
  name     = "app-tg"
  port     = 8000
  protocol = "HTTP"
}
