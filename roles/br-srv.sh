#!/bin/bash
# roles/br-srv.sh — BR-SRV: IP, пользователь, SSH

setup_base_security "br-srv"
set_ip_safe "$BR_SRV_IP" "$IF_MAIN" "192.168.1.14"
