#!/bin/bash
# roles/hq-srv.sh — HQ-SRV: IP, пользователь, SSH, DNS

setup_base_security "hq-srv"
set_ip_safe "$HQ_SRV_IP" "$IF_MAIN" "192.168.0.30"
setup_dns
