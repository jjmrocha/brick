-module(phnx).

-include("brick_log.hrl").

-behaviour(brick_phoenix).

-define(NAME, {via, brick_global, ?MODULE}).

-export([init/1, handle_call/4, handle_cast/3, handle_info/3, terminate/3, code_change/4]).
-export([reborn/2]).
-export([start/0, set/2, get/1]).

start() ->
  brick_phoenix:start(?NAME, ?MODULE,[]).

set(Key, Value) ->
  brick_phoenix:cast(?NAME, {set, Key, Value}).

get(Key) ->
  brick_phoenix:call_local(?NAME, {get, Key}).

init([]) ->
  ?LOG_INFO("Master", []),
  {ok, dict:new(), brick_hlc:timestamp()}.

handle_call({get, Key}, _From, Dict, TS) -> {reply, dict:find(Key, Dict), Dict, TS}.

handle_cast({set, Key, Value}, Dict, _TS) -> {noreply, dict:store(Key, Value, Dict), brick_hlc:timestamp()}.

handle_info(_Info, State, TS) -> {noreply, State, TS}.

terminate(_, _, _) -> ok.

code_change(_OldVsn, State, TS, _Extra) -> {ok, State, TS}.

reborn([], State, TS) ->
  ?LOG_INFO("Master (reborn)", []),
  {ok, State, TS}.
