%%% ---------------
%%% Module description
%%%
%%% Utility functions for the main game module. (gl__ prefix = game logic functions)
%%% Contains all game logic utility functions: spawn, movement, collision, and JSON encoding/decoding
%%% 
%%% functions avaialble:
%%%  - gl__spawn_random_ball/0          - returns a new (Random) ball, for a new player
%%%  - gl__move_balls/1                 - moves all balss according to their direction
%%%  - gl__handle_balls_collisions/1    - handles collisions between balls
%%% 
%%%  - decode__direction_update/1       - decodes an update message from client broswer
%%%  - encode__state                    - encodes the state in JSON, to pass to clients
%%% ---------------

-module(egs_game_module_utils).

-export([
    gl__spawn_random_ball/0,
    gl__spawn_random_food/0,
    gl__spawn_random_food_map/1,
    gl__move_balls/1,
    gl__handle_balls_collisions/1,
    gl__eat_food/2,
    decode__direction_update/1,
    encode__state/2
]).

-define(ARENA_W,    2000.0).
-define(ARENA_H,    2000.0).
-define(BALL_R,     20.0).
-define(SPEED,      10.0). % reference speed

-define(R_INC_STEP, 2.0). % ball radius increase step, when eating food
-define(FOOD_MARGIN, 10.0). % margin from border of a food at spawn


%%% Module specific cli print
print_cli(Text, Args) -> egs_utils:print_cli("GameUtils", Text, Args).


%%% Spanw a new random ball
%%% Used when a new player joins a game
gl__spawn_random_ball() ->
    % ball is a map
    #{
        x => rand:uniform() * ?ARENA_W,
        y => rand:uniform() * ?ARENA_H,
        dx => 0.0, dy => 0.0, % no direction
        radius => ?BALL_R
    }.

%%% returns a list of #Count randomly spawned balls
gl__spawn_random_food_map(Count) ->
    maps:from_list(gl__spawn_random_food_n(Count, [])).

gl__spawn_random_food_n(Count, Accum) when Count =< 0 -> 
    Accum;
gl__spawn_random_food_n(Count, Accum) ->
    gl__spawn_random_food_n(Count-1, [gl__spawn_random_food() | Accum]).

%%% Spwan a new random food food
gl__spawn_random_food() ->
    Id = erlang:unique_integer([positive, monotonic]),
    Food = #{
        x => rand:uniform() * (?ARENA_W - 2*?FOOD_MARGIN) + ?FOOD_MARGIN,
        y => rand:uniform() * (?ARENA_H - 2*?FOOD_MARGIN) + ?FOOD_MARGIN
    },
    {Id, Food}.


%%% ---------------------------
%%% MOVEMENT
%%% ---------------------------

% Move all balls: call gl__move_ball_single/1 to each one
gl__move_balls(Balls) ->
    % Execute a function over all elements of a map
    maps:map(
        % function to execute for every element of the map
        %  two args beacuse map elements are {key, value}, 
        %  so in this case {key, Ball}
        fun(_, Ball) -> 
            gl__move_ball_single(Ball) 
        end, 

        % maps to loop over
        Balls
    ).

%%% Move ball, using the information of the direction
%%%  - new position = old position + direction * SPEED (on both coordinates)
%%%  - clamps new position within area boundaries
gl__move_ball_single(Ball) ->

    % extract position and direction info
    OldX = maps:get(x,  Ball),
    OldY = maps:get(y,  Ball),
    Dx = maps:get(dx, Ball),
    Dy = maps:get(dy, Ball),
    
    % Move and clamp
    NewX = clamp(OldX + Dx * ?SPEED, 0.0, ?ARENA_W),
    NewY = clamp(OldY + Dy * ?SPEED, 0.0, ?ARENA_H),
    
    % NOTE: if we want to ensure the ENITRE ball is within boundaries,
    % we'll have to add R to the clamp { R  = maps:get(radius, Ball) }
    % right now the constraint is on the center of the ball

    % return updated ball
    Ball#{
        x => NewX, 
        y => NewY
    }.

%%% ---------------------------
%%% COLLISION
%%% ---------------------------

%%% Check all possibile pairs of ball for a collision
gl__handle_balls_collisions(Balls) ->
    % switch from maps to list, then call gl__check_collisions_list
    BallsKilled = gl__check_collisions_list(maps:to_list(Balls), []),

    % remove removed balls
    maps:without(BallsKilled, Balls).


gl__check_collisions_list([], Accum) -> Accum;
gl__check_collisions_list([_], Accum) -> Accum;
gl__check_collisions_list([{IdTarget, BallTarget} | Remaining], Accum) ->

    % list comprehension
    Removed = [

        % handle collision with the target ball, for each {IdY, BallY} from list Remaining
        gl__handle_collision(IdTarget, BallTarget, IdY, BallY) || {IdY, BallY} <- Remaining,

        % ONLY (filter) if there is a collision
        gl__check_collisions_pair(BallTarget, BallY) =:= colliding
    ],

    % loop on the remaining set of balls, increment the accumulator
    gl__check_collisions_list(Remaining, Removed ++ Accum).


%%% Checks collision of a pair of balls
gl__check_collisions_pair(Ball1, Ball2) ->

    % collision if distance is less than sum of both radius
    Distance = distance(Ball1, Ball2),
    MinDist = maps:get(radius, Ball1) + maps:get(radius, Ball2),

    case Distance =< MinDist of
        true -> colliding;
        false -> no_collision
    end.

%%% Handle collision between two balls
%%% 
%%% Returns the Id of the eaten ball
gl__handle_collision(Id1, Ball1, Id2, Ball2) ->
    % for just delete Ball2
    % it should handle one ball 'eating' another
    Id2.


%%% ---------------------------
%%% FOOD EATING
%%% ---------------------------

gl__eat_food(Balls, Foods) ->
    % switch from maps to list, then call gl__eat_food_list
    {BallsUpdatedList, RemainingFood} = gl__eat_food_list(
        maps:to_list(Balls),    % ball list
        Foods,                  % food map
        []                      % empty accumulator
    ),
    
    % from list back to map
    {maps:from_list(BallsUpdatedList), RemainingFood}.


gl__eat_food_list([], FoodMap, Accum) -> {Accum, FoodMap};
gl__eat_food_list([{IdTarget, BallTarget} | RemainingBalls], FoodMap, Accum) ->

    % list comprehension
    RemovedFoodIds = [

        % return list of food ids, from full list of Food
        IdFood || {IdFood, FoodElem} <- maps:to_list(FoodMap),

        % ONLY handle (filter) if there is a collision
        gl__check_food_collision(BallTarget, FoodElem) =:= colliding
    ],

    % increase the ball radius
    RadiusIncrease = length(RemovedFoodIds) * ?R_INC_STEP,
    UpdatedBall = BallTarget#{
        radius => maps:get(radius, BallTarget) + RadiusIncrease
    },

    % delete eaten food
    NewFood = maps:without(RemovedFoodIds, FoodMap),

    % loop on:
    gl__eat_food_list(
        RemainingBalls, % remaining balls
        NewFood, % passing only the remaining food
        [{IdTarget, UpdatedBall} | Accum] % add updated ball to accumulator
    ).



%%% Check for a collision between a ball and a food element
gl__check_food_collision(Ball, FoodElem) ->

    % check distance between ball center and food element
    Distance = distance(Ball, FoodElem),

    % food collision if distance is less then or equal to radius
    case Distance =< maps:get(radius, Ball) of
        true -> colliding;
        false -> no_collision
    end.


%%% ---------------------------
%%% ENCODING/DECODING
%%% ---------------------------


%%% Parse a message from the client broswer, containing information about the direction
%%% Uses regex function (re)
%%% 
%%% Expected format: {"dx":<float in [-1,+1]>,"dy":<float in [-1,+1]>}
%%% Example of messgae: {"dx":0.71,"dy":-0.56}
%%% 
%%% Returns {ok, Dx, Dy} or error.
decode__direction_update(Msg) ->

    % re:run(String, Pattern, Options)
    %   string is target string
    %   pattern is regex pattern (here search for dx and then dy)
    %   Options:
    %       all_but_first: avoid getting first match (the ENTIRE string)
    %       binary: return the match as a binary
    try
        % first match dx string
        {match, [DxStr]} = re:run(
            Msg, 
            "\"dx\":(-?[0-9.]+)",   % pattern to catch a possibily negative float with 1+ decimals
            [{capture, all_but_first, binary}]
        ),
        DxFloat = parse_float(DxStr),

        % then extract dy string
        {match, [DyStr]} = re:run(
            Msg, 
            "\"dy\":(-?[0-9.]+)",
            [{capture, all_but_first, binary}]
        ),
        DyFloat = parse_float(DyStr),

        % return {ok, Dx, Dy}
        {ok, DxFloat, DyFloat}

    % if there are some errors, catch all
    catch
        _:_ -> error
    end.


%%% Encodes the balls state as a JSON binary
%%% 
%%% Output format: 
%%%     {
%%%         balls:[
%%%             {"id":"<player name 1>","x":<x val>,"y":<y val>,"r":<radius>},
%%%             {"id":"<player name 2>","x":<x val>,"y":<y val>,"r":<radius>},
%%%             ...,
%%%             {"id":"<player name n>","x":<x val>,"y":<y val>,"r":<radius>}
%%%         ],
%%%         "food":[
%%%             {"id":<food id>,"x":<x val>,"y":<y val>},
%%%             ...
%%%         ]
%%%     }
encode__state(Balls, Food) ->
    %%% ref: https://www.erlang.org/docs/23/man/maps#fold-3
    %%%     fold(Fun, InitAcc, Map) -> Accumulator
    %%% description from official ref:
    %%%     Calls F(Key, Value, AccumulatorIn) for every Key-Value association in Map. 
    %%      Function fun F/3 must return a new accumulator, which is passed to the next successive call. 
    %%      This function returns the final value of the accumulator
    
    JSON_balls_data = maps:fold(
        % function used: just adds the encoded state of the current ball to the accumulator
        fun(PlayerId, Ball, Accumulator) ->
            [encode__ball(PlayerId, Ball) | Accumulator]
        end, 
        [],     % accumulator initialli set to empty list
        Balls   % map is Balls
    ),

    JSON_food_data = maps:fold(
        fun(FoodId, FoodInfo, Accumulator) ->
            [encode__food(FoodId, FoodInfo) | Accumulator]
        end,
        [],
        Food
    ),

    % with iolist_to_binary we can avoid manual loop and string join
    iolist_to_binary([
        "{\"balls\":[", lists:join(",", JSON_balls_data), "],",
        "\"food\":[", lists:join(",", JSON_food_data), "]}"
    ]).

%%% returns the encoding for a single ball
%%% Used in the general encode__state
%%% 
%%% Output format: 
%%%     {"id":"<player name>","x":<x val>,"y":<y val>,"r":<radius>}
%%% 
%%% Output example: 
%%%     {"id":"alice","x":100.0,"y":200.0,"r":20}
encode__ball(PlayerId, Ball) ->
    io_lib:format("{\"id\":\"~s\",\"x\":~.2f,\"y\":~.2f,\"r\":~p}", [
        PlayerId,
        float(maps:get(x, Ball)),
        float(maps:get(y, Ball)),
        maps:get(radius, Ball)
    ]).
    
%%% returns the encoding for a single food element
%%% Used in the general encode__state
%%% 
%%% Output format: 
%%%     {"id":<food id>,"x":<x val>,"y":<y val>}
%%% 
%%% Output example: 
%%%     {"id":123,"x":100.0,"y":200.0}
encode__food(FoodId, FoodInfo) ->
    io_lib:format("{\"id\":~p,\"x\":~.2f,\"y\":~.2f}", [
        FoodId,
        float(maps:get(x, FoodInfo)),
        float(maps:get(y, FoodInfo))
    ]).


%%% ---------------------------
%%% GENERAL UTILS
%%% ---------------------------


% Clamp between [min, max]
% useful to ensure ball is within boundaries
clamp(Value, Min, Max) ->
    max(Min, min(Max, Value)).

% euclidean distance
% work with ANY MAP CONTAINING x AND y, so balls and food
% needs {x,y} information to be put in a map
distance(Elem1, Elem2) ->
    Dx = maps:get(x, Elem1) - maps:get(x, Elem2),
    Dy = maps:get(y, Elem1) - maps:get(y, Elem2),
    math:sqrt(Dx * Dx + Dy * Dy).

% binary_to_float wrapper, to cover case of integer
parse_float(Bin) ->
    % try the standard binary_to_float
    try binary_to_float(Bin)
    % fallback on conversion to integer, then float
    catch _:_ -> float(binary_to_integer(Bin))
    end.