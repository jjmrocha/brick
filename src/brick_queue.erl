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

-include("brick_rpc.hrl").

%% ====================================================================
%% API
%% ====================================================================
-export([start/1, start/2]).
-export([start_link/1, start_link/2]).
-export([stop/1, stop/3]).

-export([flush/1]).
-export([queue_size/1]).
-export([running_count/1]).
-export([push/2]).

%% ====================================================================
%% System exports
%% ====================================================================
-export([system_continue/3, system_terminate/4, system_code_change/4]).

%% ====================================================================
%% Internal exports
%% ====================================================================
-export([do_init/3, wakeup/5]).

%% ====================================================================
%% API Implementation
%% ====================================================================
start(Options) -> start(?BRICK_RPC_NONAME, Options).

start(Name, Options) -> do_start(start, Name, Options).

start_link(Options) -> start_link(?BRICK_RPC_NONAME, Options).

start_link(Name, Options) -> do_start(start_link, Name, Options).

stop(Process) -> stop(Process, normal, infinity).

stop(Process, Reason, Timeout) -> 
	case brick_rpc:whereis_name(Process) of
		undefined -> exit(noproc);
		Pid -> proc_lib:stop(Pid, Reason, Timeout)
	end.

flush(Process) -> brick_rpc:cast(Process, flush).

queue_size(Process) -> brick_rpc:call(Process, queue_size).

running_count(Process) -> brick_rpc:call(Process, running_count).

push(Process, Fun) -> brick_rpc:cast(Process, {push, Fun}).

%% ====================================================================
%% Internal functions
%% ====================================================================
-record(options, {pool_size, priority, hibernate}).
-record(state, {queue, count}).

do_start(Type, Name, Options) ->
	case validate(Options) of
		{ok, NormalizedOptions} -> apply(proc_lib, Type, [?MODULE, do_init, [self(), Name, NormalizedOptions]]);
		Other -> Other
	end.

validate(Options) ->
	Default = #options{
			pool_size=erlang:system_info(schedulers),
			priority=normal,
			hibernate=infinity
			},
	validate(Options, Default).

validate([], Options) -> {ok, Options};
validate([{pool_size, Value}|T], Options) when is_integer(Value), Value > 0 -> 
	validate(T, Options#options{pool_size=Value});
validate([{priority, Value}|T], Options) when Value=:=low; Value=:=normal; Value=:=high; Value=:=max -> 
	validate(T, Options#options{priority=Value});
validate([{hibernate, Value}|T], Options) when (is_integer(Value) andalso Value > 0) orelse Value=:=infinity -> 
	validate(T, Options#options{hibernate=Value});
validate(_, _) -> {error, invalid_options}.

do_init(Parent, Name, Options) ->
	case brick_rpc:register_name(Name, self()) of
		true ->
			Debug = sys:debug_options([]),
			proc_lib:init_ack(Parent, {ok, self()}), 
			State = #state{queue = queue:new(), count = 0},
			loop(Parent, Debug, Name, Options, State);
		false ->
			Error = already_started,
			proc_lib:init_ack(Parent, {error, Error}),
			exit(Error)
	end.

loop(Parent, Debug, Name, Options, State) ->
	Request = receive
		Input -> Input
	after Options#options.hibernate -> hibernate
	end,
	handle_request(Request, Parent, Debug, Name, Options, State).	

handle_request(?BRICK_RPC_CAST(Msg), Parent, Debug, Name, Options, State) ->
	do_cast(Msg, Parent, Debug, Name, Options, State);	
handle_request(?BRICK_RPC_CALL(From, Msg), Parent, Debug, Name, Options, State) ->
	do_call(From, Msg, Parent, Debug, Name, Options, State);
handle_request({system, From, Request}, Parent, Debug, Name, Options, State) ->
	sys:handle_system_msg(Request, From, Parent, ?MODULE, Debug, [Name, Options, State]);	
handle_request(hibernate, Parent, Debug, Name, Options, State) ->
	proc_lib:hibernate(?MODULE, wakeup, [Parent, Debug, Name, Options, State]);
handle_request(Info, Parent, Debug, Name, Options, State) -> 
	do_info(Info, Parent, Debug, Name, Options, State).

do_call(From, Msg, Parent, Debug, Name, Options, State) ->
	{Reply, NewState} = handle_call(Msg, Options, State),
	brick_rpc:reply(From, Reply),
	loop(Parent, Debug, Name, Options, NewState).

do_cast(Msg, Parent, Debug, Name, Options, State) ->
	NewState = handle_cast(Msg, Options, State),
	loop(Parent, Debug, Name, Options, NewState).

do_info(Info, Parent, Debug, Name, Options, State) ->
	NewState = handle_info(Info, Options, State),
	loop(Parent, Debug, Name, Options, NewState).

system_continue(Parent, Debug, [Name, Options, State]) -> loop(Parent, Debug, Name, Options, State).

system_terminate(Reason, _Parent, _Debug, [Name, _Options, _State]) -> terminate(Reason, Name).

system_code_change([Name, Options, State], _Module, _OldVsn, _Extra) -> {ok, [Name, Options, State]}.

terminate(Reason, Name) ->
	brick_rpc:unregister_name(Name),
	exit(Reason).

run(Fun, Priority) -> spawn_opt(Fun, [monitor, {priority, Priority}]).

wakeup(Parent, Debug, Name, Options, State) -> loop(Parent, Debug, Name, Options, State).

%% ====================================================================
%% CALL
%% ====================================================================
handle_call(queue_size, _Options, State=#state{queue=Queue}) -> 
	Reply = {ok, queue:len(Queue)},
	{Reply, State};

handle_call(running_count, _Options, State=#state{count=Count}) -> 
	Reply = {ok, Count},
	{Reply, State};

handle_call(_Msg, _Options, State) -> 
	Reply = {error, invalid_request},
	{Reply, State}.

%% ====================================================================
%% CAST
%% ====================================================================
handle_cast({push, Fun}, #options{pool_size=Max}, State=#state{queue=Queue, count=Max}) ->
	NewQueue = queue:in(Fun, Queue),
	State#state{queue=NewQueue};
handle_cast({push, Fun}, #options{priority=Priority}, State=#state{count=Count}) ->
	run(Fun, Priority),	
	State#state{count=Count + 1};

handle_cast(flush, _Options, State) ->
	NewQueue = queue:new(),
	State#state{queue=NewQueue};

handle_cast(_Msg, _Options, State) -> State.

%% ====================================================================
%% INFO
%% ====================================================================
handle_info({'DOWN', _, _, _, _}, #options{priority=Priority}, State=#state{queue=Queue, count=Count}) ->
	case queue:out(Queue) of
		{empty, _} -> State#state{count=Count - 1};
		{{value, Fun}, NewQueue} ->
			run(Fun, Priority),
			State#state{queue=NewQueue}
	end;

handle_info(_Info, _Options, State) -> State.