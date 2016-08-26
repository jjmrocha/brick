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

-module(brick_async).

-behaviour(supervisor).

-define(SERVER, {local, ?MODULE}).
-define(DEFAULT_JOB_QUEUE, '$brick_async_default_queue').

-export([init/1]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/0]).
-export([start_queue/1, stop_queue/1]).
-export([run/1, run/2, run/3, run/4]).

start_link() -> supervisor:start_link(?SERVER, ?MODULE, []).

start_queue(JobQueue) -> supervisor:start_child(?MODULE, [{local, JobQueue}, [{hibernate, 5000}]]).

stop_queue(JobQueue) -> 
	case whereis(JobQueue) of
		undefined -> ok;
		Pid -> 
			supervisor:terminate_child(?MODULE, Pid),
			ok
	end.

run(Fun) when is_function(Fun, 0) -> run(?DEFAULT_JOB_QUEUE, Fun);
run(_Fun) -> {error, invalid_function}.

run(JobQueue, Fun) when is_atom(JobQueue), is_function(Fun, 0) ->
	case find_or_create(JobQueue) of
		{ok, Pid} -> brick_queue:push(Pid, Fun);
		Other -> Other
	end;
run(_JobQueue, _Fun) -> {error, invalid_function}.

run(Module, Function, Args) when is_atom(Module), is_atom(Function), is_list(Args) ->
	run(?DEFAULT_JOB_QUEUE, Module, Function, Args);
run(_Module, _Function, _Args) -> {error, invalid_request}.

run(JobQueue, Module, Function, Args) when is_atom(JobQueue), is_atom(Module), is_atom(Function), is_list(Args) ->
	run(JobQueue, fun() -> apply(Module, Function, Args) end);
run(_JobQueue, _Module, _Function, _Args) -> {error, invalid_request}.

%% ====================================================================
%% Behavioural functions
%% ====================================================================

init([]) ->
	error_logger:info_msg("~p starting on [~p]...\n", [?MODULE, self()]),
	JobQueue = #{id => brick_queue, start => {brick_queue, start_link, []}, restart => permanent, type => worker},
	SupFlags = #{strategy => simple_one_for_one, intensity => 2, period => 10},
	Procs = [JobQueue],
	{ok, {SupFlags, Procs}}.

%% ====================================================================
%% Internal functions
%% ====================================================================

find_or_create(JobQueue) ->
	case whereis(JobQueue) of
		undefined -> ?MODULE:start_queue(JobQueue);
		Pid -> {ok, Pid}
	end.