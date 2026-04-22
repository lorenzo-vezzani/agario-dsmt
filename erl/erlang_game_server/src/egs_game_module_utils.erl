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
    gl__update_stats/2,
    gl__eat_food/2,
    decode__direction_update/1,
    encode__state/4,
    encode__gameover/2
]).

-define(ARENA_W,    2000.0).
-define(ARENA_H,    2000.0).
-define(BALL_R,     20.0).
-define(SPEED_MAX,  10.0). % max speed, when ball is at minimum radius
-define(SPEED_MIN,  1.0). % min speed, when ball has big radius

-define(R_INC_STEP, 2.0). % ball radius increase step, when eating food
-define(FOOD_MARGIN, 10.0). % margin from border of a food at spawn


%%% Spanw a new random ball
%%% Used when a new player joins a game
gl__spawn_random_ball() ->
    % ball is a map
    #{
        x => rand:uniform() * ?ARENA_W,
        y => rand:uniform() * ?ARENA_H,
        dx => 0.0, dy => 0.0, % no direction
        radius => ?BALL_R,
        speed => ?SPEED_MAX
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
    Values = [-5, -3, -2, -1, -1, -1, 1, 1, 1, 2, 3, 5],
    FoodValue = lists:nth(rand:uniform(length(Values)), Values),
    gl__spawn_random_food(FoodValue).

gl__spawn_random_food(FoodValue) ->
    Id = erlang:unique_integer([positive, monotonic]),
    Food = #{
        x => rand:uniform() * (?ARENA_W - 2*?FOOD_MARGIN) + ?FOOD_MARGIN,
        y => rand:uniform() * (?ARENA_H - 2*?FOOD_MARGIN) + ?FOOD_MARGIN,
        value => FoodValue
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
    Speed = maps:get(speed, Ball),
    
    % Move and clamp
    NewX = clamp(OldX + Dx * Speed, 0.0, ?ARENA_W),
    NewY = clamp(OldY + Dy * Speed, 0.0, ?ARENA_H),
    
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
%%% returns {NewBallMap, List of collisions: {Eater, Killed}}
gl__handle_balls_collisions(Balls) ->
    % switch from maps to list, then call gl__check_collisions_list
    {BallsKilled, Collisions} = gl__check_collisions_list(maps:to_list(Balls), {[], []}),

    % remove removed balls
    {maps:without(BallsKilled, Balls), Collisions}.


gl__check_collisions_list([], Accum) -> Accum;
gl__check_collisions_list([_], Accum) -> Accum;
gl__check_collisions_list([{IdTarget, BallTarget} | Remaining], {KilledAccum, CollisionAccum}) ->

    % list comprehension
    CollisionResults = [

        % handle collision with the target ball, for each {IdY, BallY} from list Remaining
        gl__handle_collision(IdTarget, BallTarget, IdY, BallY) || {IdY, BallY} <- Remaining,

        % ONLY (filter) if there is a collision
        gl__check_collisions_pair(BallTarget, BallY) =:= colliding
    ],

    % CollisionResults is now an array of {Id1, Id2} and some 'equal'
    % match with {a,b} will filter out 'equal' atoms
    Killed = [KilledId || {_Eater, KilledId} <- CollisionResults],
    Collisions = [{EaterId, KilledId} || {EaterId, KilledId} <- CollisionResults],

    % loop on the remaining set of balls, increment the accumulator
    gl__check_collisions_list(Remaining, {Killed ++ KilledAccum, Collisions ++ CollisionAccum}).


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
%%% Returns the ids in this order {EaterID, KilledID}
%%% or 'equal' if they have same radius
gl__handle_collision(Id1, Ball1, Id2, Ball2) ->
    % get both radius
    R1 = maps:get(radius, Ball1),
    R2 = maps:get(radius, Ball2),

    % eater is the one with bugger radius
    if
        R1 > R2 -> {Id1, Id2};
        R2 > R1 -> {Id2, Id1};
        true -> equal
    end.

gl__update_stats(Stats, Collisions) ->

    % loop on collision lit, it's almost always empty
    lists:foldl(
        fun({EaterId, KilledId}, StatsAcc) ->

            % 1) increment kills for eater

            % Search eaterStats in the statistics map
            StatsAcc_afterEater = case maps:find(EaterId, StatsAcc) of
                {ok, EaterStats} ->
                    maps:put(
                        EaterId, % id
                        % update the kills (increment one) of the original map EaterStats
                        EaterStats#{kills => maps:get(kills, EaterStats) + 1}, 
                        StatsAcc
                    );
                % on error return map unchanged
                error -> StatsAcc
            end,

            % 2) increment deaths for killed

            % in this case the map is the return of the case AND return of the function
            case maps:find(KilledId, StatsAcc_afterEater) of
                {ok, KilledStats} ->
                    maps:put(KilledId, KilledStats#{deaths => maps:get(deaths, KilledStats) + 1}, StatsAcc_afterEater);
                error -> StatsAcc_afterEater
            end

        end,
        Stats,
        Collisions
    ).

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
    RemovedFoods = [

        % return list of food ids, from full list of Food
        {IdFood, FoodElem} || {IdFood, FoodElem} <- maps:to_list(FoodMap),

        % ONLY handle (filter) if there is a collision
        gl__check_food_collision(BallTarget, FoodElem) =:= colliding
    ],

    % sum up the eaten food values
    FoodEatenValue = gl__handle_food_eat_list(RemovedFoods),

    % radius increase = food * step_per_food_unit
    NewRadius = max(?BALL_R, maps:get(radius, BallTarget) + FoodEatenValue * ?R_INC_STEP),

    % update ball radius and its speed
    UpdatedBall = BallTarget#{
        radius => NewRadius,
        speed => calculate_speed(NewRadius)
    },

    % delete eaten food
    RemovedFoodIds = [FoodId || {FoodId, _} <- RemovedFoods],
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

gl__handle_food_eat_list(RemovedFoods) ->
    lists:foldl(

        % function to apply on every list item
        % just sum the accumulator
        fun({_FoodId, FoodElem}, Acc) ->
            Acc + maps:get(value, FoodElem) 
        end,

        % initial value of accumulator
        0, 

        % list to loop on
        RemovedFoods
    ).

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
%%%         "type": "state",
%%%         "time_ms": <integer>
%%%         "balls":[
%%%             {"id":"<player name 1>","x":<x val>,"y":<y val>,"r":<radius>},
%%%             {"id":"<player name 2>","x":<x val>,"y":<y val>,"r":<radius>},
%%%             ...,
%%%             {"id":"<player name n>","x":<x val>,"y":<y val>,"r":<radius>}
%%%         ],
%%%         "food":[
%%%             {"id":<food id>,"x":<x val>,"y":<y val>},
%%%             ...
%%%         ],
%%%         "stats":[
%%%             {"id":<player id>,"k":<kill count>,"d":<death count>},
%%%             ...
%%%         ]
%%%     }
encode__state(Balls, Food, Stats, MsElapsed) ->
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
        [],     % accumulator initially set to empty list
        Balls   % map is Balls
    ),

    JSON_food_data = maps:fold(
        fun(FoodId, FoodInfo, Accumulator) ->
            [encode__food(FoodId, FoodInfo) | Accumulator]
        end,
        [],
        Food
    ),

    JSON_stats_data = maps:fold(
        fun(PlayerId, PlayerStats, Accumulator) ->
            [encode__stats(PlayerId, PlayerStats) | Accumulator]
        end, 
        [],     % accumulator initially set to empty list
        Stats   % map is Stats
    ),

    % with iolist_to_binary we can avoid manual loop and string join
    iolist_to_binary([
        "{",
        "\"type\":\"state\",",
        "\"time_ms\":", integer_to_list(MsElapsed),",",
        "\"balls\":[", lists:join(",", JSON_balls_data), "],",
        "\"food\":[", lists:join(",", JSON_food_data), "],",
        "\"stats\":[", lists:join(",", JSON_stats_data), "]",
        "}"
    ]).



%%% returns the encoding for the game termination
%%% Output format: 
%%%     {
%%%         "type": "gameover",
%%%         "ordered_balls":[
%%%             {"id":"<player name 1>","x":<x val>,"y":<y val>,"r":<radius>},
%%%             {"id":"<player name 2>","x":<x val>,"y":<y val>,"r":<radius>},
%%%             ...,
%%%             {"id":"<player name n>","x":<x val>,"y":<y val>,"r":<radius>}
%%%         ],
%%%         "stats":[
%%%             {"id":<player id>,"k":<kill count>,"d":<death count>},
%%%             ...
%%%         ]
%%%     }
encode__gameover(Stats, Balls) ->

    % [balls] sort ball by radius (bigger first in list)
    SortedBalls = lists:sort(
        fun({_IdA, BallA}, {_IdB, BallB}) ->
            maps:get(radius, BallA) < maps:get(radius, BallB)
        end,
        maps:to_list(Balls)
    ),
    
    % [balls] get list of their encodings in JSON
    JSON_balls_data = lists:foldl(
        % Add the encoded state of the current ball to the accumulator
        fun({PlayerId, Ball}, Accumulator) ->
            [encode__ball(PlayerId, Ball) | Accumulator]
        end, 
        [],     % accumulator initially set to empty list
        SortedBalls   % map is SortedBalls
    ),

    % [statistics] sort by kill (higher first), then by deaths (lower first)
    SortedStats = lists:sort(
        fun({IdA, StatsA}, {IdB, StatsB}) ->

            % Get kill counts
            Ka = maps:get(kills, StatsA),
            Kb = maps:get(kills, StatsB),
            if
                % return if one is bigger
                Ka /= Kb -> Ka > Kb;

                % otherwise compare death count
                true ->
                    Da = maps:get(deaths, StatsA),
                    Db = maps:get(deaths, StatsB),
                    if
                        % return if one is bigger
                        Da /= Db -> Da < Db;

                        % otherwise compare final radius
                        true ->

                            % if player is dead at gameover put a radius = -1
                            Ra = case maps:find(IdA, Balls) of {ok, Ba} -> maps:get(radius, Ba); error -> -1 end,
                            Rb = case maps:find(IdB, Balls) of {ok, Bb} -> maps:get(radius, Bb); error -> -1 end,
                            Ra > Rb
                    end
            end
        end,
        maps:to_list(Stats)
    ),

    % [statistics] get their list in json (reverse beacuse accumulating in front)
    JSON_stats_data = lists:reverse(lists:foldl(
        fun({PlayerId, PlayerStats}, Accumulator) ->
            [encode__stats(PlayerId, PlayerStats) | Accumulator]
        end, 
        [],     % accumulator initially set to empty list
        SortedStats   % map is Stats
    )),

    % with iolist_to_binary we can avoid manual loop and string join
    iolist_to_binary([
        "{",
        "\"type\":\"gameover\",",
        "\"ordered_balls\":[", lists:join(",", JSON_balls_data), "],",
        "\"stats\":[", lists:join(",", JSON_stats_data), "]",
        "}"
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
%%%     {"id":<food id>,"x":<x val>,"y":<y val>,"r":<value>}
%%% 
%%% Output example: 
%%%     {"id":123,"x":100.0,"y":200.0,"r":1}
encode__food(FoodId, FoodInfo) ->
    io_lib:format("{\"id\":~p,\"x\":~.2f,\"y\":~.2f,\"r\":~p}", [
        FoodId,
        float(maps:get(x, FoodInfo)),
        float(maps:get(y, FoodInfo)),
        maps:get(value, FoodInfo)
    ]).


%%% returns the encoding for a single statitic element
%%% Used in the general encode__state
%%% 
%%% Output format: 
%%%     {"id":<player id>,"k":<kill count>,"d":<death count>}
%%% 
%%% Output example: 
%%%     {"id":123,"k":10,"d":2}
encode__stats(PlayerId, PlayerStats) ->
    io_lib:format("{\"id\":\"~s\",\"k\":~p,\"d\":~p}", [
        PlayerId,
        maps:get(kills, PlayerStats),
        maps:get(deaths, PlayerStats)
    ]).

%%% ---------------------------
%%% GENERAL UTILS
%%% ---------------------------

% Calculate a ball's speed based on its radius
% idea: hyperbolic relation, so slower as it gets bigger
% but with upper limiter on radius
calculate_speed(Radius) when Radius =< ?BALL_R ->
    ?SPEED_MAX;
calculate_speed(Radius) ->
    ?SPEED_MIN + (?SPEED_MAX - ?SPEED_MIN) * (?BALL_R / Radius).

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