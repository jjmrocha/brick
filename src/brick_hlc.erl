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

-module(brick_hlc).

-record(hlc, {l, c}).
-define(hlc_timestamp(Logical, Counter), #hlc{l = Logical, c = Counter}).

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([timestamp/0]).
-export([encode/1, decode/1]).
-export([add_seconds/2]).
-export([update/1]).
-export([compare/2, before/2]).

start_link() ->
	gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

timestamp() -> gen_server:call(?MODULE, {timestamp}).

encode(?hlc_timestamp(Logical, Counter)) ->
	<<Time:64>> = <<Logical:48, Counter:16>>,
	Time.

decode(Time) ->
	<<Logical:48, Counter:16>> = <<Time:64>>,
	?hlc_timestamp(Logical, Counter).

add_seconds(?hlc_timestamp(Logical, Counter), Seconds) ->
	MS = Seconds * ?FRACTIONS_OF_SECOND,
	?hlc_timestamp(Logical + MS, Counter).

update(ExternalTime) -> gen_server:call(?MODULE, {update, ExternalTime}).

compare(?hlc_timestamp(L1, _), ?hlc_timestamp(L2, _)) when L1 < L2 -> -1;
compare(?hlc_timestamp(L, C1), ?hlc_timestamp(L, C2)) when C1 < C2 -> -1;
compare(?hlc_timestamp(L, C), ?hlc_timestamp(L, C)) -> 0;
compare(?hlc_timestamp(_, _), ?hlc_timestamp(_, _)) -> 1;
compare(T1, T2) when T1 < T2 -> -1;
compare(T, T) -> 0;
compare(_, _) -> 1.

before(T1, T2) -> compare(T1, T2) =:= -1.

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {last}).

%% init/1
init([]) ->
	error_logger:info_msg("~p starting on [~p]...\n", [?MODULE, self()]),
	{ok, #state{last = current_timestamp()}}.

%% handle_call/3
handle_call({timestamp}, _From, State = #state{last = LastTS}) ->
	Now = wall_clock(),
	Logical = max(Now, LastTS#hlc.l),
	Counter = if
		Logical =:= LastTS#hlc.l -> LastTS#hlc.c + 1;
		true -> 0
	end,
	Timestamp = ?hlc_timestamp(Logical, Counter),
	{reply, Timestamp, State#state{last = Timestamp}};

handle_call({update, ExternalTS}, _From, State = #state{last = LastTS}) ->
	Now = wall_clock(),
	Logical = max(Now, LastTS#hlc.l, ExternalTS#hlc.l),
	Counter = if
		Logical =:= LastTS#hlc.l, LastTS#hlc.l =:= ExternalTS#hlc.l ->
			max(LastTS#hlc.c, ExternalTS#hlc.c) + 1;
		Logical =:= LastTS#hlc.l -> LastTS#hlc.c + 1;
		Logical =:= ExternalTS#hlc.l -> ExternalTS#hlc.c + 1;
		true -> 0
	end,
	Timestamp = ?hlc_timestamp(Logical, Counter),
	{reply, Timestamp, State#state{last = Timestamp}};

handle_call(_Msg, _From, State) ->
	{noreply, State}.

%% handle_cast/2
handle_cast(_Msg, State) ->
	{noreply, State}.

%% handle_info/2
handle_info(_Info, State) ->
	{noreply, State}.

%% terminate/2
terminate(_Reason, _State) ->
	ok.

%% code_change/3
code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

wall_clock() -> os:system_time(microsecond).

current_timestamp() -> ?hlc_timestamp(wall_clock(), 0).

max(A, B, C) -> max(max(A, B), C).
