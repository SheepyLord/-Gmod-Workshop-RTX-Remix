# render_policy_test.cpp

Standalone CPU check of the actual render_policy.h functions. It covers off-thread/closing/wrong
realm/missing API refusal, valid renderer options, server cvar and malformed-key rejection, and the
separate full developer gate. Compile with a C++17 compiler. No game, GPU, file or network access.
