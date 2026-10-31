# test_client.py

Offline selection and reply-identity tests for tools/rtxdebug_client.py. Multiple distinct client
processes must be selected by PID/root; duplicate windows from one process do not create a false
ambiguity. Replies require the selected PID and request ID. No windows or processes are controlled.
Run with unittest discover; scratch uses the caller's TEMP/TMP. Exit zero on success.
