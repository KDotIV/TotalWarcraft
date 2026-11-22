from wow_mock import client
from session_log_scenarios import check_session_ui

check_session_ui(client)
print('PASS: own-report suppression, self echoes, combat-deferred details, expiry/cancel/close, peer alerts, preserved error handlers, addon context, bounded activity/error logs and secret redaction.')
