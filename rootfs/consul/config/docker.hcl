rejoin_after_leave = false
leave_on_terminate = true
disable_update_check = true

autopilot {
    cleanup_dead_servers = true
    last_contact_threshold = "1m"
    min_quorum = 3
}

telemetry {
    prometheus_retention_time = "24h"
    disable_hostname = true
}
