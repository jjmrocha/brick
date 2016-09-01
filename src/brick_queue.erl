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

-module(brick_queue).

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
%% ====================================================================
%% API functions
%% ====================================================================
-export([start/1, start/2]).
-export([start_link/1, start_link/2]).
-export([stop/1, stop/3]).

-export([flush/1]).
-export([queue_size/1]).
-export([running_count/1]).
-export([push/2]).

start(Options) -> 
	gen_server:start(?MODULE, Options, []).

start(Name, Options) -> 
	gen_server:start(Name, ?MODULE, Options, []).

start_link(Options) -> 
	gen_server:start_link(?MODULE, Options, []).

start_link(Name, Options) -> 
	gen_server:start_link(Name, ?MODULE, Options, []).

stop(Process) -> stop(Process, normal, infinity).

stop(Process, Reason, Timeout) -> 
	gen_server:stop(Process, Reason, Timeout).

flush(Process) -> gen_server:cast(Process, flush).

queue_size(Process) -> gen_server:call(Process, queue_size).

running_count(Process) -> gen_server:call(Process, running_count).

push(Process, Fun) -> gen_server:cast(Process, {push, Fun}).

%% ====================================================================
%% Behavioural functions
%% ====================================================================
-record(state, {queue, count, pool_size, priority, hibernate}).

%% init/1
init(Options) ->
	Default = #state{
			queue=queue:new(),
			count=0,
			pool_size=erlang:system_info(schedulers),
			priority=normal,
			hibernate=infinity
			},
	do_init(Options, Default).

%% handle_call/3
handle_call(queue_size, _From, State=#state{queue=Queue}) ->
	Reply = {ok, queue:len(Queue)},
	{reply, Reply, State};

handle_call(running_count, _From, State=#state{count=Count}) ->
	Reply = {ok, Count},
	{reply, Reply, State};

handle_call(_Request, _From, State) ->
	{noreply, State}.

%% handle_cast/2
handle_cast({push, Fun}, State=#state{pool_size=Max, queue=Queue, count=Max}) ->
	NewQueue = queue:in(Fun, Queue),
	{noreply, State#state{queue=NewQueue}};
handle_cast({push, Fun}, State=#state{priority=Priority, count=Count}) ->
	run(Fun, Priority),
	{noreply, State#state{count=Count + 1}};

handle_cast(flush, State) ->
	NewQueue = queue:new(),
	{noreply, State#state{queue=NewQueue}};

handle_cast(_Msg, State) ->
	{noreply, State}.

%% handle_info/2
handle_info({'DOWN', _, _, _, _}, State=#state{priority=Priority, hibernate=Timeout, queue=Queue, count=Count}) ->
	case queue:out(Queue) of
		{empty, _} when Count =:= 1 -> 
			{noreply, State#state{count=0}, Timeout};
		{empty, _} -> 
			{noreply, State#state{count=Count - 1}};
		{{value, Fun}, NewQueue} ->
			run(Fun, Priority),
			{noreply, State#state{queue=NewQueue}}
	end;

handle_info(timeout, State) ->
	{noreply, State, hibernate};

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
do_init([], State=#state{hibernate=infinity}) -> {ok, State};
do_init([], State=#state{hibernate=Timeout}) -> {ok, State, Timeout};
do_init([{pool_size, Value}|T], State) when is_integer(Value), Value > 0 -> 
	do_init(T, State#state{pool_size=Value});
do_init([{priority, Value}|T], State) when Value=:=low; Value=:=normal; Value=:=high; Value=:=max -> 
	do_init(T, State#state{priority=Value});
do_init([{hibernate, Value}|T], State) when (is_integer(Value) andalso Value > 0) orelse Value=:=infinity -> 
	do_init(T, State#state{hibernate=Value});
do_init(_, _) -> {stop, invalid_options}.

run(Fun, Priority) -> spawn_opt(Fun, [monitor, {priority, Priority}]).