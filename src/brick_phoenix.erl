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

-include("brick_global.hrl").
-include("brick_hlc.hrl").

-behaviour(gen_server).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
%% ====================================================================
%% Callback functions
%% ====================================================================

-callback init(Args :: term()) ->
	{ok, ProcessState :: term()} |
	{stop, Reason :: term()}.

-callback handle_call(Request :: term(), From :: {pid(), Tag :: term()}, ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	{reply, Reply :: term(), NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{reply, Reply :: term(), NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{reply, Reply :: term(), NewProcessState :: term()} |
	{reply, Reply :: term(), NewProcessState :: term(), timeout() | hibernate} |
	{noreply, NewProcessState :: term()} |
	{noreply, NewProcessState :: term(), timeout() | hibernate} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{stop, Reason :: term(), Reply :: term(), NewProcessState :: term()} |
	{stop, Reason :: term(), NewProcessState :: term()}.

-callback handle_cast(Request :: term(), ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	{noreply, NewProcessState :: term()} |
	{noreply, NewProcessState :: term(), timeout() | hibernate} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{stop, Reason :: term(), NewProcessState :: term()}.

-callback handle_info(Info :: timeout | term(), ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	{noreply, NewProcessState :: term()} |
	{noreply, NewProcessState :: term(), timeout() | hibernate} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{noreply, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{stop, Reason :: term(), NewProcessState :: term()}.

-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	term().

-callback code_change(OldVsn :: (term() | {down, term()}), ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp(), Extra :: term()) ->
	{ok, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{error, Reason :: term()}.

-callback elected(NewProcessState :: term()) ->
	{ok, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{ok, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{stop, Reason :: term(), NewProcessState :: term()}.

-callback reborn(NewProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	{ok, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp()} |
	{ok, NewProcessState :: term(), NewClusterState :: term(), NewTS :: brick_hlc:timestamp(), timeout() | hibernate} |
	{stop, Reason :: term(), NewProcessState :: term()}.

-callback handle_state_update(ProcessState :: term(), ClusterState :: term(), TS :: brick_hlc:timestamp()) ->
	{ok, NewProcessState :: term()} |
	{stop, Reason :: term()}.

-optional_callbacks([handle_state_update/3]).

%% ====================================================================
%% API functions
%% ====================================================================
-export([start_link/3, start/3]).
-export([call_master/2, call_master/3, call_local/2, call_local/3]).
-export([cast_master/2, cast_local/2]).
-export([send_master/2, send_local/2]).

-export([is_master/1, cluster_state/1, timestamp/1]).

start_link(Name, Mod, Args) ->
	validate_name(Name),
	LocalName = local_name(Name),
	gen_server:start_link({local, LocalName}, ?MODULE, [Name, Mod, Args], []).

start(Name, Mod, Args) ->
	validate_name(Name),
	LocalName = local_name(Name),
	gen_server:start({local, LocalName}, ?MODULE, [Name, Mod, Args], []).

call_master(Name, Msg) ->
	gen_server:call(Name, Msg).

call_master(Name, Msg, Timeout) ->
	gen_server:call(Name, Msg, Timeout).

call_local(Name, Msg) when is_atom(Name) ->
	gen_server:call(Name, Msg);
call_local(Name, Msg) ->
	call_local(local_name(Name), Msg).

call_local(Name, Msg, Timeout) when is_atom(Name) ->
	gen_server:call(Name, Msg, Timeout);
call_local(Name, Msg, Timeout) ->
	call_local(local_name(Name), Msg, Timeout).

cast_master(Name, Msg) ->
	gen_server:cast(Name, Msg).

cast_local(Name, Msg) when is_atom(Name) ->
	gen_server:cast(Name, Msg);
cast_local(Name, Msg) ->
	cast_local(local_name(Name), Msg).

send_master(Name, Msg) ->
	brick_util:send(Name, Msg).

send_local(Name, Msg) when is_atom(Name) ->
	brick_util:send(Name, Msg);
send_local(Name, Msg) ->
	send_local(local_name(Name), Msg).

%% DEBUG Functions

is_master(Name) when is_atom(Name) ->
	gen_server:call(Name, {?MODULE, is_master});
is_master(Name) ->
	is_master(local_name(Name)).

cluster_state(Name) when is_atom(Name) ->
	gen_server:call(Name, {?MODULE, cluster_state});
cluster_state(Name) ->
	cluster_state(local_name(Name)).

timestamp(Name) when is_atom(Name) ->
	gen_server:call(Name, {?MODULE, timestamp});
timestamp(Name) ->
	timestamp(local_name(Name)).

%% ====================================================================
%% Behavioural functions
%% ====================================================================

-define(ROLE_MASTER, $m).
-define(ROLE_SLAVE, $s).
-define(NO_ROLE, $i).

-define(STATUS_UPDATE_QUEUE, '$brick_phoenix_async_queue').
-define(UPDATE_MSG(Data, Timestamp), {'$brick_phoenix_update_data', Data, Timestamp}).
-define(WELCOME_MSG(Slave), {'$brick_phoenix_welcome', Slave}).

-record(state, {name,
		mod,
		pdata,
		cdata,
		ts=?NO_TIMESTAMP,
		role=?NO_ROLE,
		slaves=[],
		monitors=dict:new(),
		run_update_handler}).

%% init/1
init([Name, Mod, Args]) ->
	case Mod:init(Args) of
		{ok, NewProcessState} ->
			State = #state{name=Name,
					mod=Mod,
					pdata=NewProcessState,
					run_update_handler=erlang:function_exported(Mod, handle_state_update, 1)},
			Timeout = timeout(Name),
			{ok, State, Timeout};
		{stop, Reason} ->
			{stop, Reason}
	end.

%% handle_call/3
handle_call(?WELCOME_MSG(Slave), _From, State=#state{cdata=ClusterState, ts=TS, role=?ROLE_MASTER}) ->
	State1 = #state{slaves=SlaveList} = monitor_pid(State, Slave),
	SlaveList1 = brick_util:iif(lists:member(Slave, SlaveList), SlaveList, [Slave|SlaveList]),
	{reply, ?UPDATE_MSG(ClusterState, TS), State1#state{slaves=SlaveList1}};

handle_call({?MODULE, is_master}, _From, State=#state{role=Role}) ->
	{reply, Role =:= ?ROLE_MASTER, State};

handle_call({?MODULE, cluster_state}, _From, State=#state{cdata=ClusterState}) ->
	{reply, ClusterState, State};

handle_call({?MODULE, timestamp}, _From, State=#state{ts=TS}) ->
	{reply, TS, State};

handle_call(Request, From, State=#state{mod=Mod, pdata=ProcessState, cdata=ClusterState, ts=TS}) ->
	Reply = Mod:handle_call(Request, From, ProcessState, ClusterState, TS),
	handle_reply(Reply, State);

handle_call(_Request, _From, State) ->
	{noreply, State, hibernate}.

%% handle_cast/2
handle_cast(?UPDATE_MSG(NewClusterState, NewTS), State=#state{role=?ROLE_SLAVE}) ->
	handle_update(NewClusterState, NewTS, State);

handle_cast(Msg, State=#state{mod=Mod, pdata=ProcessState, cdata=ClusterState, ts=TS}) ->
	Reply = Mod:handle_cast(Msg, ProcessState, ClusterState, TS),
	handle_reply(Reply, State);

handle_cast(_Msg, State) ->
	{noreply, State, hibernate}.

%% handle_info/2
handle_info(Info = {'DOWN', MRef, _, _, _}, State=#state{mod=Mod, pdata=ProcessState, cdata=ClusterState, ts=TS, role=?ROLE_MASTER}) ->
	case remove_ref(State, MRef) of
		ignore ->
			Reply = Mod:handle_info(Info, ProcessState, ClusterState, TS),
			handle_reply(Reply, State);
		{Pid, State1} ->
			SlaveList = lists:delete(Pid, State1#state.slaves),
			{noreply, State1#state{slaves=SlaveList}}
	end;

handle_info(?RESOLVE_REQUEST(From, Ref), State=#state{slaves=SlaveList, ts=TS}) ->
	From ! ?RESOLVE_RESPONSE(Ref, {length(SlaveList), encode_ts(TS)}),
	{noreply, State};

handle_info(Info = {'DOWN', MRef, _, _, _}, State=#state{mod=Mod, pdata=ProcessState, cdata=ClusterState, ts=TS, role=?ROLE_SLAVE}) ->
	case remove_ref(State, MRef) of
		ignore ->
			Reply = Mod:handle_info(Info, ProcessState, ClusterState, TS),
			handle_reply(Reply, State);
		{_, State1} -> {noreply, State1, 0}
	end;

handle_info(Info = timeout, State=#state{name=Name, mod=Mod, role=Role, pdata=ProcessState, cdata=ClusterState, ts=TS}) ->
	case election_day(Name, Role) of
		true ->
			case {brick_util:register_name(Name, self(), fun brick_global:resolver/3), Role} of
				{true, ?NO_ROLE} ->
					case Mod:elected(ProcessState) of
						{ok, NewProcessState, NewClusterState, NewTS} ->
							{noreply, update_state(NewProcessState, NewClusterState, NewTS, State#state{role=?ROLE_MASTER})};
						{ok, NewProcessState, NewClusterState, NewTS, hibernate} ->
							{noreply, update_state(NewProcessState, NewClusterState, NewTS, State#state{role=?ROLE_MASTER}), hibernate};
						{ok, NewProcessState, NewClusterState, NewTS, Timeout} ->
							{noreply, update_state(NewProcessState, NewClusterState, NewTS, State#state{role=?ROLE_MASTER}), Timeout};
						{stop, Reason, NewProcessState} ->
							{stop, Reason, update_state(NewProcessState, State)}
					end;
				{true, ?ROLE_SLAVE} ->
					case Mod:reborn(ProcessState, ClusterState, TS) of
						{ok, NewProcessState, NewClusterState, NewTS} ->
							{noreply, update_state(NewProcessState, NewClusterState, NewTS, State#state{role=?ROLE_MASTER})};
						{ok, NewProcessState, NewClusterState, NewTS, hibernate} ->
							{noreply, update_state(NewProcessState, NewClusterState, NewTS, State#state{role=?ROLE_MASTER}), hibernate};
						{ok, NewProcessState, NewClusterState, NewTS, Timeout} ->
							{noreply, update_state(NewProcessState, NewClusterState, NewTS, State#state{role=?ROLE_MASTER}), Timeout};
						{stop, Reason, NewProcessState} ->
							{stop, Reason, update_state(NewProcessState, State)}
					end;
				_ ->
					case brick_util:whereis_name(Name) of
						undefined -> {noreply, State, 0};
						Pid ->
							case gen_server:call(Pid, ?WELCOME_MSG(self()), 1000) of
								?UPDATE_MSG(NewClusterState, NewTS) ->
									handle_update(NewClusterState, NewTS, monitor_pid(State#state{role=?ROLE_SLAVE}, Pid));
								_ -> {noreply, State, 0}
							end
					end
			end;
		_ ->
			Reply = Mod:handle_info(Info, ProcessState, ClusterState, TS),
			handle_reply(Reply, State)
	end;

handle_info(Info, State=#state{mod=Mod, pdata=ProcessState, cdata=ClusterState, ts=TS}) ->
	Reply = Mod:handle_info(Info, ProcessState, ClusterState, TS),
	handle_reply(Reply, State);

handle_info(_Info, State) ->
	{noreply, State, hibernate}.

%% terminate/2
terminate(Reason, State=#state{name=Name, mod=Mod, pdata=ProcessState, cdata=ClusterState, ts=TS, role=?ROLE_MASTER}) ->
	demonitor_pids(State),
	Mod:terminate(Reason, ProcessState, ClusterState, TS),
	brick_util:unregister_name(Name);

terminate(_Reason, State) ->
	demonitor_pids(State).

%% code_change/3
code_change(OldVsn, State=#state{mod=Mod, pdata=ProcessState, cdata=ClusterState, ts=TS, role=?ROLE_MASTER}, Extra) ->
	case Mod:code_change(OldVsn, ProcessState, ClusterState, TS, Extra) of
		{ok, NewProcessState, NewClusterState, NewTS} ->
			{ok, update_state(NewProcessState, NewClusterState, NewTS, State)};
		{error, Reason} ->
			{error, Reason}
	end;

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

%% ====================================================================
%% Internal functions
%% ====================================================================

validate_name({global, _}) -> ok;
validate_name({via, brick_global, _}) -> ok;
validate_name(Name) -> exit({invalid_name, Name}).

local_name({global, Name}) -> Name;
local_name({via, brick_global, Name}) -> Name;
local_name(Name) when is_atom(Name) -> Name;
local_name(Name) -> exit({invalid_name, Name}).

timeout({global, _}) -> timeout_by_custer_size(nodes());
timeout({via, brick_global, brick_state}) -> timeout_by_custer_size(nodes());
timeout({via, brick_global, _}) -> timeout_by_custer_size(brick_cluster:online_nodes()).

timeout_by_custer_size([]) -> 0;
timeout_by_custer_size([_]) -> 0;
timeout_by_custer_size(_) -> 1000.

election_day(_Name, ?NO_ROLE) -> true;
election_day(Name, _Role) ->
	case brick_util:whereis_name(Name) of
		undefined -> true;
		_ -> false
	end.

encode_ts(?NO_TIMESTAMP) -> ?NO_TIMESTAMP;
encode_ts(TS) -> brick_hlc:encode(TS).

handle_reply({reply, Reply, NewProcessState, NewClusterState, NewTS}, State) ->
	{reply, Reply, update_state(NewProcessState, NewClusterState, NewTS, State)};
handle_reply({reply, Reply, NewProcessState, NewClusterState, NewTS, hibernate}, State) ->
	{reply, Reply, update_state(NewProcessState, NewClusterState, NewTS, State), hibernate};
handle_reply({reply, Reply, NewProcessState, NewClusterState, NewTS, Timeout}, State) ->
	{reply, Reply, update_state(NewProcessState, NewClusterState, NewTS, State), Timeout};
handle_reply({reply, Reply, NewProcessState}, State) ->
	{reply, Reply, update_state(NewProcessState, State)};
handle_reply({reply, Reply, NewProcessState, hibernate}, State) ->
	{reply, Reply, update_state(NewProcessState, State), hibernate};
handle_reply({reply, Reply, NewProcessState, Timeout}, State) ->
	{reply, Reply, update_state(NewProcessState, State), Timeout};
handle_reply({noreply, NewProcessState}, State) ->
	{noreply, update_state(NewProcessState, State)};
handle_reply({noreply, NewProcessState, hibernate}, State) ->
	{noreply, update_state(NewProcessState, State), hibernate};
handle_reply({noreply, NewProcessState, Timeout}, State) ->
	{noreply, update_state(NewProcessState, State), Timeout};
handle_reply({noreply, NewProcessState, NewClusterState, NewTS}, State) ->
	{noreply, update_state(NewProcessState, NewClusterState, NewTS, State)};
handle_reply({noreply, NewProcessState, NewClusterState, NewTS, hibernate}, State) ->
	{noreply, update_state(NewProcessState, NewClusterState, NewTS, State), hibernate};
handle_reply({noreply, NewProcessState, NewClusterState, NewTS, Timeout}, State) ->
	{noreply, update_state(NewProcessState, NewClusterState, NewTS, State), Timeout};
handle_reply({stop, Reason, Reply, NewProcessState}, State) ->
	{stop, Reason, Reply, update_state(NewProcessState, State)};
handle_reply({stop, Reason, NewProcessState}, State) ->
	{stop, Reason, update_state(NewProcessState, State)};
handle_reply(Other, _State) -> Other.

handle_update(NewClusterState, NewTS, State=#state{mod=Mod, pdata=ProcessState, run_update_handler=true}) ->
	brick_hlc:update(NewTS),
	case Mod:handle_state_update(ProcessState, NewClusterState, NewTS) of
		{ok, NewProcessState} ->
			{noreply, State#state{pdata=NewProcessState, cdata=NewClusterState, ts=NewTS}};
		{error, Reason} ->
			{stop, Reason, State}
	end;
handle_update(NewClusterState, NewTS, State) ->
	brick_hlc:update(NewTS),
	{noreply, State#state{cdata=NewClusterState, ts=NewTS}}.

update_state(NewProcessState, NewClusterState, NewTS, State=#state{role=?ROLE_MASTER}) ->
	uppdate_slaves(State#state.slaves, NewClusterState, NewTS),
	State#state{pdata=NewProcessState, cdata=NewClusterState, ts=NewTS};
update_state(NewProcessState, _, _, State) -> update_state(NewProcessState, State).

update_state(NewProcessState, State) ->
	State#state{pdata=NewProcessState}.

uppdate_slaves([], _, _) -> ok;
uppdate_slaves(Slaves, ClusterState, TS) ->
	brick_async:run(?STATUS_UPDATE_QUEUE, fun() ->
				publish(Slaves, ClusterState, TS)
		end).

publish([], _, _) -> ok;
publish([Pid|T], ClusterState, TS) ->
	gen_server:cast(Pid, ?UPDATE_MSG(ClusterState, TS)),
	publish(T, ClusterState, TS).

monitor_pid(State=#state{monitors=Mon}, Pid) ->
	Search = lists:filter(fun({_, P}) when P =:= Pid -> true;
				(_) -> false end, dict:to_list(Mon)),
	Mon1 = case Search of
		[] ->
			MRef = erlang:monitor(process, Pid),
			dict:store(MRef, Pid, Mon);
		_ -> Mon
	end,
	State#state{monitors=Mon1}.

demonitor_pids(#state{monitors=Mon}) ->
	lists:foreach(fun(MRef) ->
				erlang:demonitor(MRef)
		end, dict:fetch_keys(Mon)).

remove_ref(State=#state{monitors=Mon}, MRef) ->
	case dict:find(MRef, Mon) of
		error -> ignore;
		{ok, Pid} ->
			Mon1 = dict:erase(MRef, Mon),
			{Pid, State#state{monitors=Mon1}}
	end.
