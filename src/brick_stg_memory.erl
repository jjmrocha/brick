%%
%% Copyright 2016 Joaquim Rocha <jrocha@gmailbox.org>
%% 
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%

-module(brick_stg_memory).

-behaviour(brick_stg_handler).

-define(STATE_ITEM(Name, Version, Value), {Name, Version, Value}).

-export([init/1, states/1, read/2, write/4, code_change/3, terminate/1]).
%% ====================================================================
%% API functions
%% ====================================================================

init(_Args) -> {ok, []}. 

states(State) -> 
	StateList = lists:map(fun(?STATE_ITEM(Name, Version, _)) -> {Name, Version} end, State),
	{ok, StateList, State}.

read(Name, State) ->
	case lists:keyfind(Name, 1, State) of
		false -> {not_found, State};
		?STATE_ITEM(_, Version, Value) -> {ok, Value, Version, State}
	end.

write(Name, Value, Version, State) -> 
	NewState = lists:keystore(Name, 1, State, ?STATE_ITEM(Name, Version, Value)),
	{ok, NewState}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

terminate(_State) -> ok.

%% ====================================================================
%% Internal functions
%% ====================================================================


