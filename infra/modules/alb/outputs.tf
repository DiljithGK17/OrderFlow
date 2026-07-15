# ==========================================
# Outputs
# ==========================================

output "alb_arn" { value = aws_lb.this.arn }

output "alb_arn_suffix" { value = aws_lb.this.arn_suffix }

output "order_service_tg_arn" { value = aws_lb_target_group.order_service.arn }

output "alb_listener_arn" { value = aws_lb_listener.http.arn }
