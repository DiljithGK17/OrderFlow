variable "alb_dns_name" { default = "hello" }
output "out" { value = templatefile("test.tmpl", { alb_dns_name = var.alb_dns_name }) }
