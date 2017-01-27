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

-module(brick_phoenix).

-behaviour(gen_event).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
%% ====================================================================
%% Callback functions
%% ====================================================================

-callback init(Args :: term()) ->
	{ok, State :: term()} | {ok, State :: term(), timeout() | hibernate} |
	{stop, Reason :: term()} | ignore.

-callback handle_call(Request :: term(), From :: {pid(), Tag :: term()}, State :: term()) ->
	{reply, Reply :: term(), NewState :: term()} |
	{reply, Reply :: term(), NewState :: term(), timeout() | hibernate} |
	{noreply, NewState :: term()} |
	{noreply, NewState :: term(), timeout() | hibernate} |
	{stop, Reason :: term(), Reply :: term(), NewState :: term()} |
	{stop, Reason :: term(), NewState :: term()}.

-callback handle_cast(Request :: term(), State :: term()) ->
	{noreply, NewState :: term()} |
	{noreply, NewState :: term(), timeout() | hibernate} |
	{stop, Reason :: term(), NewState :: term()}.

-callback handle_info(Info :: timeout | term(), State :: term()) ->
	{noreply, NewState :: term()} |
	{noreply, NewState :: term(), timeout() | hibernate} |
	{stop, Reason :: term(), NewState :: term()}.

-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), State :: term()) ->
	term().

-callback code_change(OldVsn :: (term() | {down, term()}), State :: term(), Extra :: term()) ->
	{ok, NewState :: term()} | {error, Reason :: term()}.

-callback reborn(State :: term()) ->
	{ok, NewState :: term()} | {error, Reason :: term()}.

-optional_callbacks([reborn/1]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/3, start/3]).
-export([call/2, call/3, cast/2, send/2]).

start_link(Name, Mod, Args) ->
	validate_name(Name),
	gen_server:start_link(?MODULE, [Name, Mod, Args], []).

start(Name, Mod, Args) ->
	validate_name(Name),
	gen_server:start(?MODULE, [Name, Mod, Args], []).

call(Name, Msg) -> 
	gen_server:call(Name, Msg).

call(Name, Msg, Timeout) ->
	gen_server:call(Name, Msg, Timeout).

cast(Name, Msg) ->
	gen_server:cast(Name, Msg).

send(Name, Msg) ->
	global:send(Name, Msg).

%% ====================================================================
%% Behavioural functions
%% ====================================================================

-define(STATUS_MASTER, $m).
-define(STATUS_SLAVE, $s).
-define(STATUS_IDLE, $i).

-define(DO_INIT, {'$brick_phoenix_init'}).

-record(state, {name, mod, args, data, status=?STATUS_IDLE, slave_list=[], mon=dict:new()}).

%% init/1
init([Name, Mod, Args]) ->
	do_init(0),
	{ok, #state{name=Name, mod=Mod, args=Args}}.

%% handle_call/3
handle_call(Request, From, State=#state{mod=Mod, data=Data, status=?STATUS_MASTER}) ->
	Reply = Mod:handle_call(Request, From, Data),
	handle_reply(Reply, State);

handle_call(_Request, _From, State=#state{status=?STATUS_SLAVE}) ->
	{noreply, State};

handle_call(_Request, _From, State) ->
	{noreply, State, hibernate}.

%% handle_cast/2
handle_cast({welcome, Pid}, State=#state{data=Data, status=?STATUS_MASTER, slave_list=SlaveList}) ->
	MaxSlaves = brick_config:get_env(ha_slave_max),
	SlaveCount = erlang:length(SlaveList),
	case SlaveCount < MaxSlaves of
		true ->
			SlaveList1 = brick_util:iif(lists:member(Pid, SlaveList), SlaveList, [Pid|SlaveList]),
			publish(SlaveList1, Data, SlaveList1),
			State1 = monitor_pid(State, Pid, ?STATUS_SLAVE),
			{noreply, State1#state{slave_list=SlaveList1}};
		false ->
			gen_server:cast(Pid, {slave_list, SlaveList}),
			{noreply, State}
	end;

handle_cast(Msg, State=#state{mod=Mod, data=Data, status=?STATUS_MASTER}) ->
	Reply = Mod:handle_cast(Msg, Data),
	handle_reply(Reply, State);

handle_cast({update_data, Data}, State=#state{status=?STATUS_SLAVE}) ->
	{noreply, State#state{data=Data}};

handle_cast({update_data, Data, SlaveList}, State) ->
	SlaveList1 = lists:delete(self(), SlaveList),
	{noreply, State#state{data=Data, slave_list=SlaveList1, status=?STATUS_SLAVE}};

handle_cast({slave_list, SlaveList}, State) ->
	State1 = monitor_pids(State, SlaveList, ?STATUS_SLAVE),
	{noreply, State1#state{status=?STATUS_IDLE, slave_list=[]}, hibernate};

handle_cast(_Msg, State=#state{status=?STATUS_SLAVE}) ->
	{noreply, State};

handle_cast(_Msg, State) ->
	{noreply, State, hibernate}.

%% handle_info/2
handle_info(Info = {'DOWN', MRef, _, _, _}, State=#state{mod=Mod, data=Data, status=?STATUS_MASTER}) ->
	case remove_ref(State, MRef) of
		ignore ->
			Reply = Mod:handle_info(Info, Data),
			handle_reply(Reply, State);
		{Pid, ?STATUS_SLAVE, State1} ->
			SlaveList = lists:delete(Pid, State1#state.slave_list),
			publish(SlaveList, Data, SlaveList),
			{noreply, State1#state{slave_list=SlaveList}};
		{_, _, State1} -> {noreply, State1}
	end;

handle_info(Info, State=#state{mod=Mod, data=Data, status=?STATUS_MASTER}) ->
	Reply = Mod:handle_info(Info, Data),
	handle_reply(Reply, State);

handle_info({'DOWN', MRef, _, _, _}, State=#state{status=?STATUS_SLAVE}) ->
	case remove_ref(State, MRef) of
		ignore -> {noreply, State};
		{_, ?STATUS_MASTER, State1} -> {noreply, run_for_master(State1)};
		{_, _, State1} -> {noreply, State1}
	end;

handle_info({'DOWN', MRef, _, _, _}, State=#state{status=?STATUS_IDLE}) ->
	case remove_ref(State, MRef) of
		ignore -> {noreply, State, hibernate};
		{_, ?STATUS_MASTER, State1} -> {noreply, run_for_slave(State1)};
		{_, ?STATUS_SLAVE, State1} -> {noreply, run_for_slave(State1)};
		{_, _, State1} -> {noreply, State1, hibernate}
	end;

handle_info(?DO_INIT, State=#state{name=Name, mod=Mod, args=Args}) ->
	case brick_util:register_name(Name, self()) orelse brick_util:whereis_name(Name) =:= self() of
		true ->
			case Mod:init(Args) of
				{ok, Data} -> {noreply, update_state(State#state{status=?STATUS_MASTER}, Data)};
				{ok, Data, hibernate} -> {noreply, update_state(State#state{status=?STATUS_MASTER}, Data), hibernate};
				{ok, Data, Timeout} -> {noreply, update_state(State#state{status=?STATUS_MASTER}, Data), Timeout};
				Other ->
					brick_util:unregister_name(Name),
					case Other of
						{stop, Reason} -> {stop, Reason, State};
						ignore -> {stop, ignore, State};
						_ -> Other
					end
			end;
		false ->
			case brick_util:whereis_name(Name) of
				undefined -> 
					do_init(10),
					{noreply, State};
				Pid -> 
					gen_server:cast(Pid, {welcome, self()}),
					{noreply, monitor_pid(State, Pid, ?STATUS_MASTER)}
			end
	end;

handle_info(_Info, State) ->
	{noreply, State, hibernate}.

%% terminate/2
terminate(Reason, State=#state{name=Name, mod=Mod, data=Data, status=?STATUS_MASTER}) ->
	demonitor_pids(State),
	brick_util:unregister_name(Name),
	Mod:terminate(Reason, Data);

terminate(_Reason, State) ->
	demonitor_pids(State).

%% code_change/3
code_change(OldVsn, State=#state{mod=Mod, data=Data, status=?STATUS_MASTER}, Extra) ->
	case Mod:code_change(OldVsn, Data, Extra) of
		{ok, NewData} -> {ok, update_state(State, NewData)};
		{error, Reason} -> {error, Reason}
	end;

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

validate_name({global, _}) -> ok;
validate_name({via, brick_global, _}) -> ok;
validate_name(Name) -> exit({invalid_name, Name}).

handle_reply({reply, Reply, Data}, State) -> {reply, Reply, update_state(State, Data)};
handle_reply({reply, Reply, Data, hibernate}, State) -> {reply, Reply, update_state(State, Data), hibernate};
handle_reply({reply, Reply, Data, Timeout}, State) -> {reply, Reply, update_state(State, Data), Timeout};
handle_reply({noreply, Data}, State) -> {noreply, update_state(State, Data)};
handle_reply({noreply, Data, hibernate}, State) -> {noreply, update_state(State, Data), hibernate};
handle_reply({noreply, Data, Timeout}, State) -> {noreply, update_state(State, Data), Timeout};
handle_reply({stop, Reason , Reply, Data}, State) -> {stop, Reason , Reply, update_state(State, Data)};
handle_reply({stop, Reason, Data}, State) -> {stop, Reason, update_state(State, Data)};
handle_reply(Other, _State) -> Other.

update_state(State, Data) when State#state.data =/= Data ->
	publish(State#state.slave_list, Data),
	State#state{data=Data};
update_state(State, _Data) -> State.

publish([], _Data) -> ok;
publish([Pid|T], Data) ->
	gen_server:cast(Pid, {update_data, Data}),
	publish(T, Data).

publish([], _Data, _SlaveList) -> ok;
publish([Pid|T], Data, SlaveList) ->
	gen_server:cast(Pid, {update_data, Data, SlaveList}),
	publish(T, Data, SlaveList).

monitor_pid(State=#state{mon=Mon}, Pid, Status) ->
	Search = lists:filter(fun({_, {P, _}}) when P =:= Pid -> true; 
				(_) -> false end, dict:to_list(Mon)),
	MRef = case Search of
		[] -> erlang:monitor(process, Pid);
		[{Ref, _}] -> Ref
	end,
	Mon1 = dict:store(MRef, {Pid, Status}, Mon),
	State#state{mon=Mon1}.

monitor_pids(State, Pids, Status) ->
	lists:foldl(fun(Pid, S) -> 
				monitor_pid(S, Pid, Status) 
		end, State, Pids).

demonitor_pids(#state{mon=Mon}) ->
	lists:foreach(fun(MRef) -> 
				erlang:demonitor(MRef) 
		end, dict:fetch_keys(Mon)).

remove_ref(State=#state{mon=Mon}, MRef) ->
	case dict:find(MRef, Mon) of
		error -> ignore;
		{ok, {Pid, Status}} ->
			Mon1 = dict:erase(MRef, Mon),
			{Pid, Status, State#state{mon=Mon1}}
	end.

run_for_master(State=#state{name=Name, mod=Mod, data=Data}) ->
	case brick_util:register_name(Name, self()) of
		true -> 
			case erlang:function_exported(Mod, reborn, 1) of
				true ->
					case Mod:reborn(Data) of
						{ok, NewData} -> 
							State1 = update_state(State, NewData), 
							State1#state{status=?STATUS_MASTER};
						{error, Reason} ->
							error_logger:error_msg("~p: ~p (~p) return {error, ~p}\n", [?MODULE, Mod, self(), Reason]),
							do_init(0),
							State#state{status=?STATUS_MASTER}
					end;
				_ -> State#state{status=?STATUS_MASTER}
			end;
		false ->
			case brick_util:whereis_name(Name) of
				undefined -> 
					timer:sleep(10),
					run_for_master(State);
				Pid -> monitor_pid(State, Pid, ?STATUS_MASTER)
			end					
	end.	

run_for_slave(State=#state{name=Name}) ->
	case brick_util:whereis_name(Name) of
		undefined ->
			timer:sleep(10),
			run_for_slave(State);
		Pid -> 
			gen_server:cast(Pid, {welcome, self()}),
			monitor_pid(State, Pid, ?STATUS_MASTER)
	end.	

do_init(0) -> self() ! ?DO_INIT;
do_init(Timeout) -> timer:send_after(Timeout, ?DO_INIT).
