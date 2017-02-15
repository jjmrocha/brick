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

-module(brick_stg_file).

-include("brick_log.hrl").
-include("brick_stg.hrl").

-behaviour(brick_stg_handler).

-define(DATA(Version, Data), {{version, Version}, {state, Data}}).
-define(ITEM(Name, Value), {Name, Value}).

-export([init/1, read/1, write/3, code_change/3, terminate/1]).
%% ====================================================================
%% API functions
%% ====================================================================

init(Args) ->
	case lists:keyfind(file_name, 1, Args) of
		false ->
			?LOG_ERROR("No value for parameter ~p", [file_name]),
			{stop, invalid_configuration};
		{_, FileName} -> {ok, FileName};
	end.

read(FileName) ->
	case read_file(FileName) of
		{ok, ?DATA(Version, Data)} ->
			List = [ #stg_record{key=Key, value=Value} || ?ITEM(Key, Value) <- Data ],
			{ok, List, Version, FileName};
		{error, enoent} -> {ok, [], ?STG_NO_VERSION, FileName};
		{error, Reason} -> {stop, Reason, FileName}
	end.

write(List, Version, FileName) ->
	Data = [ ?ITEM(Key, Value) || #stg_record{key=Key, value=Value} <- List],
	case write_file(FileName, ?DATA(Version, Data)) of
		ok -> {ok, FileName};
		{error, Reason} -> {stop, Reason, FileName}
	end.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

terminate(_State) -> ok.

%% ====================================================================
%% Internal functions
%% ====================================================================

read_file(FileName) -> file:script(FileName).

write_file(FileName, Data) ->
	case file:open(FileName, write) of
		{ok, H} ->
			io:format(H, "~p.", [Data]),
			file:close(H);
		{error, Reason} -> {error, Reason}
	end.
