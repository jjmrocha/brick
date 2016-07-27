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

-module(brick_stg_file).

-behaviour(brick_stg_handler).

-define(STATE_ITEM(Name, Version, Value), {Name, Version, Value}).

-export([init/1, names/1, read/2, write/4, code_change/3, terminate/1]).
%% ====================================================================
%% API functions
%% ====================================================================

init(Args) ->
	case lists:keyfind(file_name, 1, Args) of
		false -> 
			error_logger:error_msg("~p: No value for parameter ~p\n", [?MODULE, file_name]),
			{stop, invalid_configuration};
		{_, FileName} -> {ok, FileName}
	end. 

names(FileName) -> 
	case read_file(FileName) of
		{ok, Data} -> 
			Names = lists:map(fun(?STATE_ITEM(Name, _, _)) -> Name end, Data),
			{ok, Names, FileName}.		
		{error, Reason} -> {stop, Reason, FileName}
	end.

read(Name, FileName) ->
	case read_file(FileName) of
		{ok, Data} -> 
			case lists:keyfind(Name, 1, Data) of
				false -> {not_found, FileName};
				?STATE_ITEM(_, Version, Value) -> {ok, Value, Version, FileName}
			end;			
		{error, Reason} -> {stop, Reason, FileName}
	end.

write(Name, Value, Version, FileName) -> 
	case read_file(FileName) of
		{ok, Data} -> 
			NewData = lists:keystore(Name, 1, Data, ?STATE_ITEM(Name, Version, Value)),
			case write_file(FileName, NewData) of
				ok -> {ok, FileName};
				{error, Reason} -> {stop, Reason, FileName}
			end;
		{error, Reason} -> {stop, Reason, FileName}
	end.	

code_change(_OldVsn, FileName, _Extra) -> {ok, FileName}.

terminate(_FileName) -> ok.

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

