-module(egs_utils).
-export([print_cli/3]).

-define(RESET,   "\e[0m").

% Standard
-define(BLACK,          "\e[30m").
-define(RED,            "\e[31m").
-define(GREEN,          "\e[32m").
-define(YELLOW,         "\e[33m").
-define(BLUE,           "\e[34m").
-define(MAGENTA,        "\e[35m").
-define(CYAN,           "\e[36m").
-define(WHITE,          "\e[37m").

% Bright
-define(GRAY,           "\e[90m").
-define(BRIGHT_RED,     "\e[91m").
-define(BRIGHT_GREEN,   "\e[92m").
-define(BRIGHT_YELLOW,  "\e[93m").
-define(BRIGHT_BLUE,    "\e[94m").
-define(BRIGHT_MAGENTA, "\e[95m").
-define(BRIGHT_CYAN,    "\e[96m").
-define(BRIGHT_WHITE,   "\e[97m").

% print format:
% [HH:MM:SS][ModuleName][PID]
print_cli(Module, Text, Args) ->
    {{_, Mo, D}, {H, M, S}} = calendar:local_time(),
    Timestamp = io_lib:format("~2..0b:~2..0b::~2..0b:~2..0b:~2..0b", [Mo, D, H, M, S]),
    io:format(
        "~s[~s ~s ~s~s/~s~s ~s ~s~s/~s~s ~p ~s~s]~s " ++ Text ++ "~n",
        [
            ?BRIGHT_RED,
            ?GRAY, Timestamp, ?RESET,
            ?BRIGHT_RED,?RESET,  
            ?YELLOW, Module, ?RESET,
            ?BRIGHT_RED,?RESET,  
            ?GREEN, self(), ?RESET,
            ?BRIGHT_RED,?RESET
        ] ++ Args
    ).