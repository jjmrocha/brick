%%
%% Copyright 2016-17 Joaquim Rocha <jrocha@gmailbox.org>
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

-include("brick_stg.hrl").

-behaviour(brick_stg_handler).

-export([init/1, read/1, write/3, code_change/3, terminate/1]).
%% ====================================================================
%% API functions
%% ====================================================================

-record(state, {version, data=[]}).

init(_Args) ->
	State = #state{version=?STG_NO_VERSION},
	{ok, State}.

read(State=#state{version=Version, data=Data}) ->
	{ok, Data, Version, State}.

write(Data, Version, State) ->
	{ok, State#state{version=Version, data=Data}}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

terminate(_State) -> ok.

%% ====================================================================
%% Internal functions
%% ====================================================================
