-module(phnx).

-include("brick_log.hrl").

-behaviour(brick_phoenix).

-define(NAME, {via, brick_global, ?MODULE}).

-export([init/1, handle_call/5, handle_cast/4, handle_info/4, terminate/4, code_change/5]).
-export([elected/1, reborn/3]).
-export([start/0, set/2, get/1]).

start() ->
	brick_phoenix:start(?NAME, ?MODULE,[]).

set(Key, Value) ->
	brick_phoenix:cast_master(?NAME, {set, Key, Value}).

get(Key) ->
	brick_phoenix:call_local(?NAME, {get, Key}).

init([]) ->
	?LOG_INFO("Master", []),
	{ok, []}.

handle_call({get, Key}, _From, State, Dict, _TS) -> {reply, dict:find(Key, Dict), State}.

handle_cast({set, Key, Value}, State, Dict, _TS) -> {noreply, State, dict:store(Key, Value, Dict), brick_hlc:timestamp()}.

handle_info(_Info, State, _Dict, _TS) -> {noreply, State}.

terminate(_, _, _, _) -> ok.

code_change(_OldVsn, State, Dict, TS, _Extra) -> {ok, State, Dict, TS}.

elected(State) -> {ok, State, dict:new(), brick_hlc:timestamp()}.

reborn(State, Dict, TS) ->
	?LOG_INFO("Master (reborn)", []),
	{ok, State, Dict, TS}.
